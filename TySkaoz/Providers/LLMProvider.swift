import Foundation

protocol LLMProvider: Sendable {
    var id: String { get }
    var displayName: String { get }

    func availability() async -> ProviderAvailability
    func chat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>
}

enum ProviderAvailability: Equatable {
    case ready
    case unavailable(reason: String)
}

struct ChatMessage: Hashable, Sendable {
    enum Role: String, Hashable, Sendable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String

    init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

extension ChatMessage {
    /// Convenience: map a stored Message to a ChatMessage. Returns nil for
    /// `.toolCall` / `.toolResult` entries — those aren't representable in
    /// the current text-only ChatMessage shape and will be threaded through
    /// the providers separately in Bloc 3.
    init?(_ message: Message) {
        let role: Role
        switch message.role {
        case .user:                  role = .user
        case .assistant:             role = .assistant
        case .toolCall, .toolResult: return nil
        }
        self.init(role: role, content: message.content)
    }
}
