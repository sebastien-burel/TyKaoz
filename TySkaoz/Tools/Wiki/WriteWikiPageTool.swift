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
        Creates or updates a wiki page at the given relative path. When
        overwriting, pass expected_hash from a previous read_page to
        detect concurrent edits. The tool normalises wikilinks (turns
        [[Title]] into [[id|Title]] when the target exists), writes
        the file, auto-commits via git, and re-indexes so search_wiki
        sees the change immediately.
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

        // 3. Normalise wikilinks against the live page index.
        let normalised = try await Self.normaliseWikilinks(args.content, pool: context.pool)
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
