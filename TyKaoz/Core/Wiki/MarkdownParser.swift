import Foundation
import TyKaozKit

/// Parsed representation of one wiki page on disk.
struct ParsedPage: Hashable {
    let id: String
    let title: String
    let type: String?
    /// One-line description for the index catalog: frontmatter `summary:`
    /// when present, else the first body line of prose.
    let summary: String?
    let sources: [String]
    let createdAt: Date?
    let updatedAt: Date?
    let body: String
    let chunks: [ParsedChunk]
    let wikilinks: [Wikilink]
    let contentHash: String
}

/// One chunk = one section delimited by markdown headings. `headingPath` is
/// the breadcrumb from the page title down to the heading that introduces
/// this section, encoded as a JSON array string at persistence time.
struct ParsedChunk: Hashable {
    let ordinal: Int
    let headingPath: [String]
    let text: String
}

/// A `[[...]]` reference inside the page body. The indexer resolves `raw`
/// against existing pages (by id then by title) to populate `dst_page_id`
/// in the `edges` table; unresolved links stay pendouillants.
struct Wikilink: Hashable {
    /// Target as written: either a page id (`[[abc-123|Alias]]`) or a
    /// page title (`[[Phase 6]]`).
    let raw: String
    /// Display text after `|`. `nil` when the link is bare.
    let alias: String?
}

/// Lightweight markdown parser tailored to the wiki use case. Not a
/// general-purpose markdown engine — only does the three things the
/// indexer needs: YAML-ish frontmatter, `[[wikilinks]]`, heading-based
/// chunking. Pure function, no I/O.
enum MarkdownParser {

    /// `path` is the on-disk path relative to `wiki/` — used as a fallback
    /// for the page id and title when the frontmatter is missing.
    static func parse(_ content: String, path: String) -> ParsedPage {
        let (frontmatter, body) = splitFrontmatter(content)
        let fields = parseFrontmatter(frontmatter)

        let fallbackTitle = (path as NSString)
            .lastPathComponent
            .replacingOccurrences(of: ".md", with: "")
        let fallbackID = fields["id"]?.first
            ?? path.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ".md", with: "")

        return ParsedPage(
            id: fallbackID,
            title: fields["title"]?.first ?? fallbackTitle,
            type: fields["type"]?.first.flatMap { $0.isEmpty ? nil : $0 },
            summary: deriveSummary(fields: fields, body: body),
            sources: fields["sources"] ?? [],
            createdAt: fields["created"]?.first.flatMap(parseDate),
            updatedAt: fields["updated"]?.first.flatMap(parseDate),
            body: body,
            chunks: chunk(body),
            wikilinks: extractWikilinks(in: body),
            contentHash: HashStore.sha256(content)
        )
    }

    /// One-line summary for the index catalog: frontmatter `summary:` wins;
    /// otherwise the first non-empty, non-heading body line, capped at
    /// 200 characters.
    static func deriveSummary(fields: [String: [String]], body: String) -> String? {
        if let explicit = fields["summary"]?.first, !explicit.isEmpty {
            return String(explicit.prefix(200))
        }
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            return String(trimmed.prefix(200))
        }
        return nil
    }

    // MARK: - Frontmatter

    /// Splits a `---\n…\n---\n` block off the top of the document. Returns
    /// `(nil, content)` when no frontmatter is present.
    static func splitFrontmatter(_ content: String) -> (String?, String) {
        let lines = content.components(separatedBy: "\n")
        guard lines.first == "---" else { return (nil, content) }
        guard let closingIndex = lines.dropFirst().firstIndex(of: "---") else {
            return (nil, content)
        }
        let fmLines = lines[1..<closingIndex]
        let bodyLines = lines[(closingIndex + 1)...]
        return (
            fmLines.joined(separator: "\n"),
            bodyLines.joined(separator: "\n")
        )
    }

    /// Tiny YAML subset: `key: value` and `key: [a, b, c]`. Anything more
    /// exotic is ignored; the wiki's frontmatter is a convention we
    /// control, not a general YAML document.
    static func parseFrontmatter(_ raw: String?) -> [String: [String]] {
        guard let raw, !raw.isEmpty else { return [:] }
        var out: [String: [String]] = [:]
        for line in raw.components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("[") && value.hasSuffix("]") {
                let inner = value.dropFirst().dropLast()
                out[key] = inner
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } else {
                out[key] = [value]
            }
        }
        return out
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private static func parseDate(_ raw: String) -> Date? {
        iso8601Formatter.date(from: raw)
    }

    // MARK: - Chunking by headings

    /// Splits `body` into sections demarcated by `#`-prefixed lines.
    /// Each chunk carries the breadcrumb of headings down to its anchor.
    /// Content before the first heading is captured as one chunk with an
    /// empty heading path.
    static func chunk(_ body: String) -> [ParsedChunk] {
        var chunks: [ParsedChunk] = []
        var currentPath: [String] = []
        var currentText: [String] = []
        var ordinal = 0

        func flush() {
            let text = currentText
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            chunks.append(ParsedChunk(
                ordinal: ordinal,
                headingPath: currentPath,
                text: text
            ))
            ordinal += 1
        }

        for line in body.components(separatedBy: "\n") {
            if let (level, title) = parseHeading(line) {
                flush()
                currentText.removeAll(keepingCapacity: true)
                while currentPath.count >= level { currentPath.removeLast() }
                while currentPath.count < level - 1 { currentPath.append("") }
                currentPath.append(title)
            } else {
                currentText.append(line)
            }
        }
        flush()
        return chunks
    }

    /// Returns `(level, title)` for ATX headings (`# Title`, `## Title`…).
    /// Setext headings (`Title\n===`) are not supported — the wiki style is
    /// ATX-only by convention.
    private static func parseHeading(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for c in line {
            if c == "#" { level += 1 } else { break }
        }
        guard level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Wikilinks

    /// Matches `[[…]]` references in two forms:
    ///   `[[Page Title]]`
    ///   `[[id-or-title|Alias display]]`
    /// Order matters — the alias-bearing branch must be tried first.
    static func extractWikilinks(in body: String) -> [Wikilink] {
        let pattern = /\[\[([^\]\|]+)\|([^\]]+)\]\]|\[\[([^\]]+)\]\]/
        var out: [Wikilink] = []
        for match in body.matches(of: pattern) {
            if let raw = match.output.1, let alias = match.output.2 {
                out.append(Wikilink(
                    raw: String(raw).trimmingCharacters(in: .whitespaces),
                    alias: String(alias).trimmingCharacters(in: .whitespaces)
                ))
            } else if let raw = match.output.3 {
                out.append(Wikilink(
                    raw: String(raw).trimmingCharacters(in: .whitespaces),
                    alias: nil
                ))
            }
        }
        return out
    }
}
