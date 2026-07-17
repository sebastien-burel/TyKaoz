import Foundation
import TyKaozKit

extension ChatMessage {
    /// Maps a stored Message to a ChatMessage. Returns `nil` for `.error`
    /// messages — they're app-generated notices that must never reach the
    /// LLM. Tool roles carry their metadata through so providers can
    /// serialise them into their own wire formats.
    init?(_ message: Message, imageURLs: [URL] = []) {
        let role: Role
        switch message.role {
        case .user:       role = .user
        case .assistant:  role = .assistant
        case .toolCall:   role = .toolCall
        case .toolResult: role = .toolResult
        case .error:      return nil
        }
        self.init(
            role: role,
            content: message.content,
            imageURLs: imageURLs,
            toolCallID: message.toolCallID,
            toolName: message.toolName,
            toolIsError: message.toolIsError,
            reasoningContent: message.reasoningContent,
            thoughtSignature: message.thoughtSignature
        )
    }
}
