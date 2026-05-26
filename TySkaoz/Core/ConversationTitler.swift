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
        guard conversation.messages.count >= 2 else { return nil }

        let exchange = conversation.messages
            .prefix(2)
            .map { message -> String in
                let label = (message.role == .user) ? "Utilisateur" : "Assistant"
                return "\(label) : \(message.content)"
            }
            .joined(separator: "\n\n")

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
            return nil
        }

        let cleaned = clean(collected)
        return cleaned.isEmpty ? nil : cleaned
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
