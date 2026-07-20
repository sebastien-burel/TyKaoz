import Foundation

/// Append-only operations journal (`wiki/log.md`) — the second special
/// file of the LLM-wiki pattern. Written deterministically by the app
/// (tool writes, ingests, lint runs), never by the model: git already
/// journals every write, log.md makes the history legible *inside* the
/// wiki itself.
enum WikiLog {

    /// Pure entry formatting: `## [2026-07-04] write | Titre (chemin)`.
    static func entry(op: String, detail: String, date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return "## [\(formatter.string(from: date))] \(op) | \(detail)"
    }

    static let header = """
    ---
    id: log
    title: Journal
    type: log
    ---

    > Journal des opérations, généré automatiquement — ne pas modifier.
    """

    /// Appends one entry to `wiki/log.md`, creating the file (with its
    /// frontmatter header) on first use. Best-effort, like GitRunner: a
    /// failed journal line must never fail the operation it records.
    static func append(op: String, detail: String, in wikiRoot: URL, date: Date = .now) {
        let url = wikiRoot.appendingPathComponent("log.md")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? header
        let line = entry(op: op, detail: detail, date: date)
        let updated = existing.hasSuffix("\n")
            ? existing + "\n" + line + "\n"
            : existing + "\n\n" + line + "\n"
        try? updated.write(to: url, atomically: true, encoding: .utf8)
    }
}
