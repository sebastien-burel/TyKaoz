import Foundation
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
        Creates or updates a wiki page at the given relative path.

        BEFORE writing, ALWAYS call `search_wiki` with the topic so
        you don't create a duplicate of an existing page — the wiki
        rejects writes whose title clashes with another page (different
        path). If you find an existing match, call `read_page` to get
        its current hash, then call this tool with the SAME path and
        `expected_hash` to update it in place.

        When overwriting, pass expected_hash from the read_page result
        to detect concurrent edits. The tool normalises wikilinks
        (turns [[Title]] into [[id|Title]] when the target exists),
        stamps the frontmatter `created` / `updated` dates, writes the
        file, auto-commits via git, and re-indexes so search_wiki sees
        the change immediately.
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
        let fullURL = context.wikiRoot.appendingPathComponent(args.path)

        // 2. Compare-and-swap.
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

        // 2b. Anti-duplicate guard: if some OTHER page already carries
        //     the title the agent wants to write under this new path,
        //     refuse and tell the agent to update that page instead.
        //     Title comparison is case-insensitive and trims spaces —
        //     "Le Sucre" and "le sucre" are the same wiki concept.
        if try await Self.titleCollision(
            withContent: args.content,
            atPath: args.path,
            pool: context.pool
        ) {
            throw ToolError.execution(message: """
                Une page wiki avec ce titre existe déjà sous un autre \
                chemin. Lance d'abord `search_wiki` pour la trouver, \
                puis `read_page` pour récupérer son hash, puis appelle \
                `write_wiki_page` avec ce chemin existant + \
                expected_hash pour la mettre à jour.
                """)
        }

        // 3. Normalise wikilinks against the live page index.
        let withLinks = try await Self.normaliseWikilinks(args.content, pool: context.pool)
        // 4. Stamp frontmatter dates so the agent can't guess them
        //    wrong (it doesn't know the current date). `created` is
        //    preserved from disk on overwrite; `updated` always gets
        //    today.
        let normalised = Self.stampFrontmatter(withLinks, existingPageURL: fullURL)
        let newHash = HashStore.sha256(normalised)

        // 4. Atomic write.
        try FileManager.default.createDirectory(
            at: fullURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try normalised.write(to: fullURL, atomically: true, encoding: .utf8)

        // 5. Audit log via git. Best-effort.
        let slug = args.path.replacingOccurrences(of: "/", with: "-")
        let committed = GitRunner.commit(
            message: "agent: write \(slug)",
            in: context.wikiRoot,
            relativePath: args.path
        )

        // 6. Sync re-index so search_wiki sees the new content.
        // Phase 2's file-watch will take this over.
        _ = try await context.makeIndexer().reindexAll()

        let gitLine = committed ? "git: commit créé" : "git: indisponible, écriture quand même"
        return """
        Écrit \(args.path)
        hash: \(newHash)
        \(gitLine)
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

    /// Returns true when the title parsed out of `content` already
    /// belongs to another page in the DB whose path is different
    /// from `atPath`. Comparison is case-insensitive on the
    /// trimmed title.
    static func titleCollision(
        withContent content: String,
        atPath: String,
        pool: DatabasePool
    ) async throws -> Bool {
        let (fm, _) = MarkdownParser.splitFrontmatter(content)
        guard let rawTitle = MarkdownParser.parseFrontmatter(fm)["title"]?.first else {
            return false  // no title → no collision logic possible
        }
        let normalized = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        return try await pool.read { db in
            let conflict = try Row.fetchOne(db, sql: """
                SELECT path FROM pages
                WHERE lower(trim(title)) = ? AND path != ?
                LIMIT 1;
            """, arguments: [normalized, atPath])
            return conflict != nil
        }
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
