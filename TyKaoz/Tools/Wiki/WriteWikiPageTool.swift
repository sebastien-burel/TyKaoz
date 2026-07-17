import Foundation
import TyKaozKit
import GRDB

/// The only wiki tool that mutates state. Combines decisions Q2, Q6, Q7:
///
/// - Q7 (CAS): the caller must pass `expected_hash` from a previous
///   `read_page` when overwriting an existing page; mismatch throws
///   `ConflictError` so the agent re-reads and re-reasons.
/// - Q6 (wikilink normalization): `[[Title]]` references are rewritten
///   to `[[id|Title]]` against the current page index before the file
///   lands on disk, so renames don't silently break links.
/// - Q2 (git audit log): each write triggers an auto-commit on the
///   wiki directory — best-effort, won't fail the tool if git is
///   unavailable.
///
/// After the write the indexer runs synchronously so a subsequent
/// `search_wiki` sees the new content. Phase 2's file-watch will
/// take this over.
struct WriteWikiPageTool: Tool {
    let context: WikiContext

    let spec = ToolSpec(
        name: "write_wiki_page",
        description: """
        Creates or updates a wiki page.

        To UPDATE an existing page, first `read_page` it, merge your
        changes into its full content, then call this with that page's
        path. A page's title is its identity: if a page with the same
        title already exists, the tool updates THAT page in place
        whatever path you pass — so always send the COMPLETE merged
        markdown, since anything you omit is overwritten.

        Optionally pass expected_hash from the read_page result to
        detect a concurrent edit (the write is rejected if the page
        changed since you read it). The tool normalises wikilinks
        (turns [[Title]] into [[id|Title]] when the target exists),
        stamps the frontmatter `created` / `updated` dates, writes the
        file, auto-commits via git, and re-indexes so search_wiki sees
        the change immediately.

        Follow the conventions in the page with id "agents" (types,
        no duplicates, at least one [[link]], sources in frontmatter).
        index.md and log.md are app-managed — never write them.
        This is for knowledge (topics, people, projects); a small personal
        preference (name, language, tone) goes in save_memory instead.
        """,
        inputSchemaJSON: """
        {
          "type": "object",
          "properties": {
            "path": {
              "type": "string",
              "description": "Relative path under wiki/ (e.g. notes/foo.md). Must end in .md."
            },
            "content": {
              "type": "string",
              "description": "Full markdown content including YAML frontmatter."
            },
            "expected_hash": {
              "type": "string",
              "description": "Hash returned by a previous read_page. Omit when creating a new page."
            }
          },
          "required": ["path", "content"],
          "additionalProperties": false
        }
        """
    )

    private struct Args: Decodable {
        let path: String
        let content: String
        let expected_hash: String?
    }

    func execute(arguments: Data) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: arguments)

        // 1. Validate path: must be under wiki/, must be .md, no escape.
        guard args.path.hasSuffix(".md"), !args.path.contains(".."), !args.path.hasPrefix("/") else {
            throw ToolError.execution(message: "Chemin invalide. Attendu : relatif sous wiki/, terminé en .md.")
        }
        // App-managed files: index.md is regenerated after every reindex
        // and log.md is the append-only journal — a model write would be
        // overwritten or corrupt the history.
        let reserved = ["index.md", "log.md"]
        guard !reserved.contains(args.path.lowercased()) else {
            throw ToolError.execution(message: """
                \(args.path) est géré par l'application (catalogue/journal). \
                Écris tes contenus dans d'autres pages.
                """)
        }

        // 2. Resolve the real target. A page's title is its identity: if
        //    a page with this title already exists under a different path
        //    spelling (e.g. the model writes `family/clara.md` when the
        //    page lives at `family-clara.md`), update THAT page in place
        //    rather than refusing. Refusing made weak local models loop
        //    forever; every write is git-committed, so an overwrite stays
        //    recoverable.
        let existing = try await Self.findCollidingPage(
            withContent: args.content,
            atPath: args.path,
            pool: context.pool,
            wikiRoot: context.wikiRoot
        )
        let targetPath = existing?.path ?? args.path
        let fullURL = context.wikiRoot.appendingPathComponent(targetPath)

        // 3. Compare-and-swap against the resolved target.
        if let expected = args.expected_hash {
            let currentContent = (try? String(contentsOf: fullURL, encoding: .utf8)) ?? ""
            let currentHash = currentContent.isEmpty ? nil : HashStore.sha256(currentContent)
            if currentHash != expected {
                throw ToolError.execution(message: """
                    Conflit : la page a été modifiée depuis ta dernière lecture \
                    (hash attendu \(expected), trouvé \(currentHash ?? "<aucun>")). \
                    Relis-la, refais ton raisonnement, et réessaie.
                    """)
            }
        }

        // 4. Normalise wikilinks against the live page index.
        let withLinks = try await Self.normaliseWikilinks(args.content, pool: context.pool)
        // 5. Stamp frontmatter dates so the agent can't guess them
        //    wrong (it doesn't know the current date). `created` is
        //    preserved from disk on overwrite; `updated` always gets
        //    today.
        let normalised = Self.stampFrontmatter(withLinks, existingPageURL: fullURL)
        let newHash = HashStore.sha256(normalised)

        // 6. Atomic write.
        try FileManager.default.createDirectory(
            at: fullURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try normalised.write(to: fullURL, atomically: true, encoding: .utf8)

        // 7. Journal, then sync re-index (+ index.md refresh) so
        //    search_wiki sees the new content immediately.
        let title = MarkdownParser.parse(normalised, path: targetPath).title
        WikiLog.append(op: "write", detail: "\(title) (\(targetPath))", in: context.wikiRoot)
        try await context.reindexAll()

        // 8. Audit log via git. Best-effort. Stage-all (no relativePath)
        //    so the page, log.md and the regenerated index.md land in one
        //    commit.
        let slug = targetPath.replacingOccurrences(of: "/", with: "-")
        let committed = GitRunner.commit(
            message: "agent: write \(slug)",
            in: context.wikiRoot
        )

        let gitLine = committed ? "git: commit créé" : "git: indisponible, écriture quand même"
        let retargetNote = existing.map {
            "\nNote : page existante « \($0.title) » mise à jour en place ; "
                + "utilise le chemin \(targetPath) pour les prochaines modifications."
        } ?? ""
        return """
        Écrit \(targetPath)
        hash: \(newHash)
        \(gitLine)\(retargetNote)
        """
    }

    /// Overwrites `updated` to today, and `created` to today when the
    /// file is new (or preserves whatever the existing on-disk version
    /// had). Whatever the agent wrote in those fields is ignored —
    /// dates are tool-controlled metadata.
    static func stampFrontmatter(
        _ content: String,
        existingPageURL: URL,
        today: Date = .now
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let todayStr = formatter.string(from: today)

        // Preserve the existing `created` when the file already exists.
        let preservedCreated: String? = (
            try? String(contentsOf: existingPageURL, encoding: .utf8)
        ).flatMap { existing in
            let (fm, _) = MarkdownParser.splitFrontmatter(existing)
            return MarkdownParser.parseFrontmatter(fm)["created"]?.first
        }
        let createdStr = preservedCreated ?? todayStr

        let (frontmatterRaw, body) = MarkdownParser.splitFrontmatter(content)
        let fmLines: [String] = frontmatterRaw?
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init) ?? []

        var rewritten: [String] = []
        var sawCreated = false
        var sawUpdated = false
        for line in fmLines {
            if line.hasPrefix("created:") {
                rewritten.append("created: \(createdStr)")
                sawCreated = true
            } else if line.hasPrefix("updated:") {
                rewritten.append("updated: \(todayStr)")
                sawUpdated = true
            } else {
                rewritten.append(line)
            }
        }
        if !sawCreated { rewritten.append("created: \(createdStr)") }
        if !sawUpdated { rewritten.append("updated: \(todayStr)") }

        return "---\n\(rewritten.joined(separator: "\n"))\n---\n\(body)"
    }

    struct CollidingPage {
        let path: String
        let title: String
        let hash: String
        let content: String
    }

    /// Looks up another page (different `path`) whose title matches —
    /// case-insensitive, trimmed. Returns its full live content + hash
    /// so the caller can hand them back to the agent without forcing
    /// an extra `read_page` round-trip.
    static func findCollidingPage(
        withContent content: String,
        atPath: String,
        pool: DatabasePool,
        wikiRoot: URL
    ) async throws -> CollidingPage? {
        let (fm, _) = MarkdownParser.splitFrontmatter(content)
        guard let rawTitle = MarkdownParser.parseFrontmatter(fm)["title"]?.first else {
            return nil
        }
        let normalized = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        guard let row = try await pool.read({ db in
            try Row.fetchOne(db, sql: """
                SELECT path, title FROM pages
                WHERE lower(trim(title)) = ? AND path != ?
                LIMIT 1;
            """, arguments: [normalized, atPath])
        }) else { return nil }

        let existingPath: String = row["path"]
        let existingTitle: String = row["title"]
        let url = wikiRoot.appendingPathComponent(existingPath)
        let liveContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let hash = HashStore.sha256(liveContent)

        return CollidingPage(
            path: existingPath,
            title: existingTitle,
            hash: hash,
            content: liveContent
        )
    }

    /// Builds the `title → id` index from the DB and runs the pure
    /// `WikilinkNormalizer` against the new content.
    static func normaliseWikilinks(
        _ content: String,
        pool: DatabasePool
    ) async throws -> String {
        let titleToID: [String: String] = try await pool.read { db in
            var out: [String: String] = [:]
            let rows = try Row.fetchAll(db, sql: "SELECT id, title FROM pages;")
            for row in rows {
                out[row["title"]] = row["id"]
            }
            return out
        }
        return WikilinkNormalizer.normalize(content) { title in
            titleToID[title]
        }
    }
}
