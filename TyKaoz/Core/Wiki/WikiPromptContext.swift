import Foundation

/// Builds the wiki preamble injected as system context on each send —
/// the behavioral loop of the LLM-wiki pattern: without it the model has
/// no reason to consult or maintain the wiki. Combines a fixed
/// instruction header, the user's conventions (`AGENTS.md`) and the
/// generated catalog (`index.md`), under a hard character budget so
/// small-context models aren't drowned.
enum WikiPromptContext {

    static let defaultBudget = 2_500

    /// Always-on: the model reads the wiki to answer.
    static let readHeader = """
    Tu disposes d'un wiki personnel persistant (ta mémoire à long terme).
    Avant de répondre à une question factuelle sur l'utilisateur, ses \
    projets ou ses connaissances, appelle `search_wiki`.
    """

    /// Deliberate-write policy (default): the user decides what is saved.
    static let manualWritePolicy = """
    N'enrichis PAS le wiki de toi-même : ne crée et ne modifie une page que \
    si l'utilisateur te le demande explicitement, ou via l'action « Wikifier ».
    """

    /// Auto-curation policy: the model maintains the wiki proactively.
    static let autoWritePolicy = """
    Quand l'utilisateur t'apprend une information durable, crée ou mets à \
    jour une page via `write_wiki_page` en suivant les conventions ci-dessous.
    """

    /// Pure assembly under budget. `autoCuration` picks the write policy —
    /// off by default, so writes stay deliberate. The conventions matter
    /// more than the catalog, so the index is truncated first, then AGENTS.
    /// Frontmatter is stripped from both files — pure noise for the model.
    static func build(
        agentsMD: String?,
        indexMD: String?,
        autoCuration: Bool = false,
        budget: Int = defaultBudget
    ) -> String {
        let header = readHeader + "\n" + (autoCuration ? autoWritePolicy : manualWritePolicy)
        var parts: [String] = [header]
        var remaining = budget - header.count

        if let agents = strippedBody(agentsMD), !agents.isEmpty, remaining > 0 {
            let clipped = String(agents.prefix(remaining))
            parts.append(clipped)
            remaining -= clipped.count
        }
        if let index = strippedBody(indexMD), !index.isEmpty, remaining > 0 {
            let label = "Contenu actuel du wiki :\n"
            let clipped = String(index.prefix(max(0, remaining - label.count)))
            if !clipped.isEmpty {
                parts.append(label + clipped)
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// Reads `AGENTS.md` and `index.md` from disk and assembles the
    /// preamble. Files are small and reads are per-send — no caching.
    static func load(
        wikiRoot: URL,
        autoCuration: Bool = false,
        budget: Int = defaultBudget
    ) -> String {
        let agents = try? String(
            contentsOf: wikiRoot.appendingPathComponent("AGENTS.md"),
            encoding: .utf8
        )
        let index = try? String(
            contentsOf: wikiRoot.appendingPathComponent("index.md"),
            encoding: .utf8
        )
        return build(agentsMD: agents, indexMD: index, autoCuration: autoCuration, budget: budget)
    }

    private static func strippedBody(_ content: String?) -> String? {
        guard let content else { return nil }
        let (_, body) = MarkdownParser.splitFrontmatter(content)
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
