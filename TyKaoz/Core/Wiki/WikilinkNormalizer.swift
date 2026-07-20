import Foundation

/// Decision Q6 — every `[[Titre]]` written by the LLM is rewritten to
/// `[[id|Titre]]` once we can resolve the target page. Targets that don't
/// match a known page are left alone; the linter surfaces them as
/// "concepts manquants".
///
/// Pure function: takes a body and a resolver closure, returns the
/// normalised body. The indexer plugs a real resolver (DB lookup);
/// tests can inject any dictionary.
enum WikilinkNormalizer {

    /// Resolves a raw wikilink target (title or id) to the canonical
    /// page id, or `nil` when no page matches.
    typealias Resolver = (String) -> String?

    /// Rewrites every `[[Titre]]` that resolves to a known page into
    /// `[[id|Titre]]`. Idempotent — calling twice produces the same
    /// output. Already-resolved `[[id|alias]]` forms are passed through
    /// unchanged.
    static func normalize(_ body: String, resolve: Resolver) -> String {
        let pattern = /\[\[([^\]\|]+)\|([^\]]+)\]\]|\[\[([^\]]+)\]\]/
        return body.replacing(pattern) { match in
            // alias-bearing form already targets an id — pass through.
            if let raw = match.output.1, let alias = match.output.2 {
                return "[[\(raw)|\(alias)]]"
            }
            // bare form: try to resolve.
            guard let raw = match.output.3 else { return String(match.output.0) }
            let title = String(raw).trimmingCharacters(in: .whitespaces)
            if let id = resolve(title) {
                // Already in [[id|…]] shape by accident (the raw text *is*
                // an existing page's id)? Keep alias = title for readability.
                return "[[\(id)|\(title)]]"
            }
            return "[[\(title)]]"
        }
    }
}
