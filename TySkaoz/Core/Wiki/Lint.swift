import Foundation
import GRDB

/// Snapshot of structural issues in the wiki. Pure data — no I/O, no
/// rendering. The Phase 6 tool wraps this and formats it for the agent.
struct LintReport: Hashable {
    var orphans: [Orphan]
    var danglingLinks: [DanglingLink]
    var missingConcepts: [MissingConcept]

    struct Orphan: Hashable {
        let pageID: String
        let title: String
    }

    struct DanglingLink: Hashable {
        let srcPageID: String
        let srcTitle: String
        let dstTitleRaw: String
    }

    /// A title referenced from at least two pages but with no `pages`
    /// row backing it. These are the strongest "candidate to create"
    /// signals: multiple authors thought the concept should exist.
    struct MissingConcept: Hashable {
        let titleRaw: String
        let references: Int
    }
}

/// Deterministic half of the `lint_wiki` checklist from Phase 6 of
/// PLAN_TYKAOZ_WIKI: orphan pages, dangling wikilinks, and recurring
/// missing concepts. The LLM half (contradictions, obsolescence,
/// sémantique duplicates) is layered on top by a separate prompt
/// pipeline — out of scope for this struct.
enum Lint {
    static func run(_ db: Database) throws -> LintReport {
        let orphans = try Row.fetchAll(db, sql: """
            SELECT p.id, p.title
            FROM pages p
            LEFT JOIN edges e ON e.dst_page_id = p.id
            WHERE e.dst_page_id IS NULL
            ORDER BY p.title;
        """).map {
            LintReport.Orphan(pageID: $0["id"], title: $0["title"])
        }

        let dangling = try Row.fetchAll(db, sql: """
            SELECT e.src_page_id, p.title AS src_title, e.dst_title_raw
            FROM edges e
            JOIN pages p ON p.id = e.src_page_id
            WHERE e.dst_page_id IS NULL
            ORDER BY e.dst_title_raw, p.title;
        """).map {
            LintReport.DanglingLink(
                srcPageID: $0["src_page_id"],
                srcTitle: $0["src_title"],
                dstTitleRaw: $0["dst_title_raw"]
            )
        }

        let missing = try Row.fetchAll(db, sql: """
            SELECT dst_title_raw, COUNT(*) AS refs
            FROM edges
            WHERE dst_page_id IS NULL
            GROUP BY dst_title_raw
            HAVING refs >= 2
            ORDER BY refs DESC, dst_title_raw;
        """).map {
            LintReport.MissingConcept(
                titleRaw: $0["dst_title_raw"],
                references: $0["refs"]
            )
        }

        return LintReport(
            orphans: orphans,
            danglingLinks: dangling,
            missingConcepts: missing
        )
    }
}
