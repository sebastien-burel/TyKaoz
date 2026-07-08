import Foundation

/// Shared slug maker for wiki page ids and raw-source filenames.
enum Slug {
    /// Lowercase, French diacritic stripped, non-alphanum → hyphens.
    /// Stable across platforms — no localized magic, just ASCII.
    static func make(_ raw: String) -> String {
        let folded = raw.folding(options: .diacriticInsensitive, locale: .init(identifier: "fr_FR"))
        let lower = folded.lowercased()
        var out = ""
        var lastWasDash = false
        for c in lower {
            if c.isLetter || c.isNumber {
                out.append(c)
                lastWasDash = false
            } else if !lastWasDash, !out.isEmpty {
                out.append("-")
                lastWasDash = true
            }
        }
        if out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "page-\(UUID().uuidString.prefix(8))" : out
    }
}
