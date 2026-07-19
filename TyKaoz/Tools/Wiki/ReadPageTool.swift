import Foundation
import TyKaozKit
import GRDB

/// Reads one wiki page from disk (markdown body), enriched with its
/// content hash so the agent can pass `expected_hash` to a later
/// `write_wiki_page` call for compare-and-swap edits.
struct ReadPageTool: Tool {
    let context: WikiContext

    let spec = ToolSpec(
        name: "read_page",
        description: """
        Reads a single wiki page. Identify it by its stable id (preferred)
        or its current title. Returns the full markdown content plus the
        page's current content hash — feed that hash back into
        `write_wiki_page` if you intend to overwrite, to detect concurrent
        edits.
        """,
        inputSchemaJSON: """
        {
          "type": "object",
          "properties": {
            "id":    { "type": "string", "description": "Stable page id." },
            "title": { "type": "string", "description": "Current page title (exact match)." }
          },
          "additionalProperties": false
        }
        """
    )

    private struct Args: Decodable {
        let id: String?
        let title: String?
    }

    func execute(arguments: Data) async throws -> String {
        let args = (try? JSONDecoder().decode(Args.self, from: arguments))
            ?? Args(id: nil, title: nil)
        guard args.id != nil || args.title != nil else {
            throw ToolError.execution(message: "read_page requires either 'id' or 'title'.")
        }

        // Resolve to a path via the DB (the indexed truth) so the agent
        // can use the title without knowing the on-disk layout.
        let row: (id: String, path: String, hash: String)? = try await context.pool.read { db in
            if let id = args.id {
                return try Row.fetchOne(db, sql: """
                    SELECT id, path, content_hash FROM pages WHERE id = ?;
                """, arguments: [id]).map { ($0["id"], $0["path"], $0["content_hash"]) }
            }
            return try Row.fetchOne(db, sql: """
                SELECT id, path, content_hash FROM pages WHERE title = ?;
            """, arguments: [args.title]).map { ($0["id"], $0["path"], $0["content_hash"]) }
        }
        guard let row else {
            throw ToolError.execution(message: "Page introuvable.")
        }

        let url = context.wikiRoot.appendingPathComponent(row.path)
        let content = try String(contentsOf: url, encoding: .utf8)
        // Defensive: if the file's been edited outside the indexer the
        // hash on disk won't match `pages.content_hash`. Surface the
        // live hash so the agent's CAS uses the right baseline.
        let liveHash = HashStore.sha256(content)

        return """
        --- id: \(row.id)
        --- path: \(row.path)
        --- hash: \(liveHash)\(liveHash == row.hash ? "" : "  (index stale, expected \(row.hash))")

        \(content)
        """
    }
}
