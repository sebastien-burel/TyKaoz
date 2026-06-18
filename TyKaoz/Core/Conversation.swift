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
        /// An `.error` message produced during this turn (a failed send),
        /// rendered as an inline banner. `nil` when the turn succeeded.
        let error: Message?

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

            var all: [Message] = []
            while i < messages.endIndex, messages[i].role != .user {
                all.append(messages[i])
                i = messages.index(after: i)
            }

            // `.error` messages render as their own inline banner, so pull
            // them out of the turn's body (otherwise they'd be hidden in
            // the collapsible intermediate-steps disclosure).
            let error = all.last { $0.role == .error }
            // Drop empty assistant placeholders (no text, reasoning or
            // image): they only ever rendered as a "…" bubble, which the
            // live streaming indicator now replaces.
            let collected = all.filter { msg in
                if msg.role == .error { return false }
                let isEmptyPlaceholder = msg.role == .assistant
                    && msg.content.isEmpty
                    && (msg.reasoningContent ?? "").isEmpty
                    && (msg.attachments ?? []).isEmpty
                return !isEmptyPlaceholder
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
                    finalAssistant: final,
                    error: error
                ))
            } else {
                result.append(Turn(
                    userMessage: user,
                    intermediates: collected,
                    finalAssistant: nil,
                    error: error
                ))
            }
        }
        return result
    }
}
