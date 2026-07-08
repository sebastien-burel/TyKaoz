import Foundation

/// Generates a short title for a conversation by asking the active LLM to
/// summarize the first user/assistant exchange. Used to auto-rename
/// "Nouvelle conversation" once the user has had their first turn.
enum ConversationTitler {

    /// Sentinel used everywhere we create a fresh conversation. We only
    /// auto-rename when the title still matches this — otherwise the user
    /// already renamed manually and we respect that.
    static let defaultTitle = "Nouvelle conversation"

    /// Streams a title from the provider. Returns nil on failure (network,
    /// stream error, empty result). Returns a cleaned, length-capped title
    /// on success.
    static func generate(
        from conversation: Conversation,
        using provider: any LLMProvider
    ) async -> String? {
        // Use the first user message paired with the *last* assistant
        // message that actually has text. Tool-using turns emit a short
        // preamble ("I'll first check your location…") that, fed to a
        // titler, produces useless summaries of the intent rather than of
        // the answer. The final assistant message holds the real content.
        guard let userMessage = conversation.messages
                .first(where: { $0.role == .user }),
              let assistantMessage = conversation.messages
                .last(where: { $0.role == .assistant && !$0.content.isEmpty })
        else { return nil }

        let exchange = """
        Utilisateur : \(userMessage.content)

        Assistant : \(assistantMessage.content)
        """

        let prompt = """
        Donne-moi un titre très court (3 à 5 mots, en français) qui résume ce début de conversation. Réponds UNIQUEMENT avec le titre, sans guillemets, sans préfixe, sans ponctuation finale.

        \(exchange)
        """

        var collected = ""
        do {
            for try await event in provider.chat(
                messages: [ChatMessage(role: .user, content: prompt)],
                tools: []
            ) {
                if case .textDelta(let delta) = event {
                    collected += delta
                }
            }
        } catch {
            // Stream error (or a reasoning model that never emitted content):
            // still give the conversation a usable title.
            return fallback(from: userMessage.content)
        }

        let cleaned = clean(collected)
        // Reasoning models sometimes answer entirely in their thinking
        // channel and leave the content empty — fall back rather than
        // leaving "Nouvelle conversation".
        return cleaned.isEmpty ? fallback(from: userMessage.content) : cleaned
    }

    /// Deterministic title from the first user message when the LLM can't
    /// (or won't) produce one. Flattened, trimmed, capped.
    static func fallback(from userContent: String) -> String {
        let flat = userContent
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return defaultTitle }
        guard flat.count > 40 else { return flat }
        return String(flat.prefix(40)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Strips quotes, surrounding whitespace, trailing punctuation, and caps
    /// at 60 characters. Pure function — kept testable.
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Some models lead with "Titre : ..." — drop that.
        for prefix in ["Titre :", "Titre:", "Title:"] {
            if s.lowercased().hasPrefix(prefix.lowercased()) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Strip a single pair of surrounding quotes (straight, curly, French).
        let quotePairs: [(Character, Character)] = [
            ("\"", "\""), ("\u{201C}", "\u{201D}"), ("\u{00AB}", "\u{00BB}"), ("'", "'")
        ]
        for (open, close) in quotePairs {
            if s.first == open, s.last == close, s.count >= 2 {
                s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Strip trailing punctuation, then any whitespace it leaves behind.
        while let last = s.last, ".,;:!?".contains(last) {
            s.removeLast()
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Length cap (defensive — short titles fit the sidebar nicely).
        if s.count > 60 {
            s = String(s.prefix(60)).trimmingCharacters(in: .whitespaces)
        }

        return s
    }
}
