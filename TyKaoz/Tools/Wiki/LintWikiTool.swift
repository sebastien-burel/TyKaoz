import Foundation
import KaozKit
import GRDB

/// Surfaces the deterministic structural issues in the wiki:
/// orphan pages, dangling wikilinks, recurring missing concepts.
/// The agent decides whether each one warrants a follow-up action
/// (create a page, fix a link, leave alone).
struct LintWikiTool: Tool {
    let context: WikiContext

    let spec = ToolSpec(
        name: "lint_wiki",
        description: """
        Reports structural issues in the wiki: orphan pages (no incoming
        links), dangling wikilinks (point to nothing), and recurring
        missing concepts (titles referenced from multiple pages with no
        backing page yet — strong candidates to create). Pure SQL,
        cheap to call.
        """,
        inputSchemaJSON: """
        {
          "type": "object",
          "properties": {},
          "additionalProperties": false
        }
        """
    )

    func execute(arguments: Data) async throws -> String {
        let report = try await context.pool.read { db in
            try Lint.run(db)
        }
        return Self.format(report)
    }

    static func format(_ report: LintReport) -> String {
        var sections: [String] = []

        let orphans = report.orphans
        if orphans.isEmpty {
            sections.append("## Orphelins\nAucun.")
        } else {
            let lines = orphans.map { "- **\($0.title)** (id: \($0.pageID))" }
            sections.append("## Orphelins (\(orphans.count))\n\(lines.joined(separator: "\n"))")
        }

        let dangling = report.danglingLinks
        if dangling.isEmpty {
            sections.append("## Liens pendouillants\nAucun.")
        } else {
            let lines = dangling.map { "- `\($0.srcTitle)` → [[\($0.dstTitleRaw)]]" }
            sections.append("## Liens pendouillants (\(dangling.count))\n\(lines.joined(separator: "\n"))")
        }

        let missing = report.missingConcepts
        if missing.isEmpty {
            sections.append("## Concepts manquants\nAucun.")
        } else {
            let lines = missing.map { "- **\($0.titleRaw)** (\($0.references) références)" }
            sections.append("## Concepts manquants (\(missing.count))\n\(lines.joined(separator: "\n"))")
        }

        return sections.joined(separator: "\n\n")
    }
}
