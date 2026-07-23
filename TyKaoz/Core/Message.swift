import Foundation
import KaozKit

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
        /// An app-generated failure notice (a send that threw). `content`
        /// holds the user-facing error text. Shown inline in the
        /// transcript and **never** sent back to the LLM.
        case error
    }

    /// A file attached to a message (currently images for VLM models).
    /// Only metadata is persisted in the conversation JSON; the bytes live
    /// as sidecar files managed by `ConversationStore`. `filename` is
    /// `<uuid>.<ext>` within the conversation's attachments folder.
    struct Attachment: Identifiable, Hashable, Codable {
        let id: UUID
        let filename: String

        init(id: UUID = UUID(), filename: String) {
            self.id = id
            self.filename = filename
        }
    }

    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date

    /// Image attachments on a `.user` message. nil/empty for text-only.
    var attachments: [Attachment]?

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

    /// Gemini 2.5+ binds each emitted part to a cryptographic "thought
    /// signature" (base64). The next request must echo it back next to the
    /// matching part, or the API responds with HTTP 400. We carry it on
    /// the message that owns the part — mostly `.toolCall` messages.
    var thoughtSignature: String?

    /// Label of the model that answered this turn (e.g. "Sur ce Mac ·
    /// gpt-oss-20b"). Set on the `.user` message at send time so the UI
    /// can mark where the active model changed mid-conversation. Purely
    /// display metadata — never sent to the LLM.
    var model: String?

    /// Performance metrics for an assistant turn (token counts, throughput,
    /// time-to-first-token). Set when the provider can measure them. Display
    /// metadata only — never sent to the LLM.
    var metrics: GenerationMetrics?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = .now,
        attachments: [Attachment]? = nil,
        toolCallID: String? = nil,
        toolName: String? = nil,
        toolIsError: Bool? = nil,
        reasoningContent: String? = nil,
        thoughtSignature: String? = nil,
        model: String? = nil,
        metrics: GenerationMetrics? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.attachments = attachments
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.toolIsError = toolIsError
        self.reasoningContent = reasoningContent
        self.thoughtSignature = thoughtSignature
        self.model = model
    }
}
