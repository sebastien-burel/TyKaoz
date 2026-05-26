import Foundation

struct Message: Identifiable, Hashable, Codable {
    enum Role: String, Hashable, Codable {
        case user
        case assistant
        /// The assistant requested a tool. `content` holds the raw JSON
        /// arguments the model emitted (kept verbatim so the registry can
        /// decode it however the tool likes). `toolName` and `toolCallID`
        /// must be set on messages with this role.
        case toolCall
        /// The app's response to a `toolCall`. `content` holds the tool
        /// output (or error message). `toolCallID` matches the call.
        case toolResult
    }

    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date

    /// Provider-assigned id correlating a tool call with its result. nil for
    /// user / assistant / system text messages.
    var toolCallID: String?

    /// Name of the tool invoked. Set on `.toolCall`. nil otherwise.
    var toolName: String?

    /// True when a `.toolResult` represents an error (tool throw, unknown
    /// tool, invalid args). The LLM still receives the content as feedback.
    var toolIsError: Bool?

    /// Some "thinking" models (DeepSeek v4, etc.) emit a chain of thought
    /// in a separate `reasoning_content` field. The provider expects that
    /// content to be sent back unchanged in the next turn's history,
    /// otherwise it refuses (HTTP 400). We don't display it (yet) but
    /// persist it so subsequent rounds round-trip correctly.
    var reasoningContent: String?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = .now,
        toolCallID: String? = nil,
        toolName: String? = nil,
        toolIsError: Bool? = nil,
        reasoningContent: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.toolIsError = toolIsError
        self.reasoningContent = reasoningContent
    }
}
