import Foundation
import KaozKit

/// Wraps `Finder.search(_:)` and formats the result list as a compact
/// markdown blob the agent can paste into its reasoning.
struct SearchWikiTool: Tool {
    let context: WikiContext

    let spec = ToolSpec(
        name: "search_wiki",
        description: """
        Hybrid search across the local knowledge wiki: KNN over chunk
        embeddings + BM25 over chunk text, fused and graph-expanded
        1–2 hops. Returns the most relevant pages with snippet, hop
        distance to a direct match, and a relevance score. For a full
        table of contents instead, call read_page with id "index".
        """,
        inputSchemaJSON: """
        {
          "type": "object",
          "properties": {
            "query": {
              "type": "string",
              "description": "Natural-language search query."
            },
            "limit": {
              "type": "integer",
              "description": "Max number of pages to return (default 6)."
            }
          },
          "required": ["query"],
          "additionalProperties": false
        }
        """
    )

    private struct Args: Decodable {
        let query: String
        let limit: Int?
    }

    func execute(arguments: Data) async throws -> String {
        let args = (try? JSONDecoder().decode(Args.self, from: arguments))
            ?? Args(query: "", limit: nil)
        guard !args.query.isEmpty else {
            throw ToolError.execution(message: "search_wiki requires a 'query' argument.")
        }
        guard let embedder = context.embedder else {
            throw ToolError.execution(message: "Aucun fournisseur d'embeddings configuré (cf. réglages → wiki).")
        }
        let finder = Finder(pool: context.pool, embedder: embedder)
        let results = try await finder.search(args.query, limit: args.limit ?? 6)
        return Self.format(results)
    }

    /// One result per block. Headings + scores let the agent scan
    /// without needing to re-rank itself.
    static func format(_ results: [Retrieved]) -> String {
        guard !results.isEmpty else {
            return "Aucun résultat dans le wiki pour cette requête."
        }
        return results.enumerated().map { i, r in
            let hopMark = r.hops == 0 ? "match direct" : "+\(r.hops) hop"
            let breadcrumb = r.headingPath?.joined(separator: " › ") ?? ""
            let head = "[\(i + 1)] **\(r.title)** (id: \(r.pageID), \(hopMark), score \(String(format: "%.2f", r.score)))"
            let crumb = breadcrumb.isEmpty ? "" : "\n_\(breadcrumb)_"
            return "\(head)\(crumb)\n\(r.snippet)"
        }.joined(separator: "\n\n---\n\n")
    }
}
