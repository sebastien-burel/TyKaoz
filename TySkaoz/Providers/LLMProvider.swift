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
    /// Convenience: map from a stored Message (which only has user/assistant
    /// roles today) to a ChatMessage.
    init(_ message: Message) {
        let role: Role
        switch message.role {
        case .user:      role = .user
        case .assistant: role = .assistant
        }
        self.init(role: role, content: message.content)
    }
}
