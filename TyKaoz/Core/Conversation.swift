import Foundation

struct Conversation: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    var messages: [Message]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        messages: [Message] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.messages = messages
    }

    /// A single user → assistant exchange, possibly with tool round-trips in
    /// between. Used by the UI to collapse intermediate steps (preambles,
    /// tool calls, tool results) once the turn is complete.
    struct Turn: Identifiable, Hashable {
        let userMessage: Message
        /// Anything between the user message and the final assistant text:
        /// preamble assistant messages, `.toolCall`, `.toolResult`.
        let intermediates: [Message]
        /// The last `.assistant` message of the turn with non-empty content.
        /// `nil` while the turn is still streaming and no final text yet.
        let finalAssistant: Message?

        var id: UUID { userMessage.id }
    }

    /// Groups `messages` into turns starting at each `.user` message. The
    /// final assistant message of each turn is the *last* `.assistant` with
    /// non-empty content — anything before it (intermediate preambles +
    /// tool messages) is folded into `intermediates`.
    var turns: [Turn] {
        var result: [Turn] = []
        var i = messages.startIndex
        while i < messages.endIndex {
            guard messages[i].role == .user else {
                i = messages.index(after: i)
                continue
            }
            let user = messages[i]
            i = messages.index(after: i)

            var collected: [Message] = []
            while i < messages.endIndex, messages[i].role != .user {
                collected.append(messages[i])
                i = messages.index(after: i)
            }

            if let finalIdx = collected.lastIndex(where: {
                $0.role == .assistant
                    && (!$0.content.isEmpty || !($0.attachments ?? []).isEmpty)
            }) {
                let final = collected[finalIdx]
                let intermediates = Array(collected[..<finalIdx])
                result.append(Turn(
                    userMessage: user,
                    intermediates: intermediates,
                    finalAssistant: final
                ))
            } else {
                result.append(Turn(
                    userMessage: user,
                    intermediates: collected,
                    finalAssistant: nil
                ))
            }
        }
        return result
    }
}
