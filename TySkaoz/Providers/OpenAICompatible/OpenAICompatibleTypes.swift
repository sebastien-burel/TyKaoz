import Foundation

/// Decoded shape of one streamed chunk from the OpenAI-compatible
/// `/v1/chat/completions` API (used by OpenAI, Mistral, DeepSeek). Both
/// content text and partial tool-call payloads can appear, sometimes
/// together.
struct OpenAICompatibleChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let toolCalls: [ToolCallDelta]?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
                case reasoningContent = "reasoning_content"
            }
        }

        struct ToolCallDelta: Decodable {
            let index: Int?
            let id: String?
            /// "function" in the current API; carried as-is for forwards
            /// compatibility but we don't switch on it.
            let type: String?
            let function: FunctionDelta?
        }

        struct FunctionDelta: Decodable {
            let name: String?
            let arguments: String?
        }

        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }
    let choices: [Choice]
}

struct OpenAICompatibleModelsResponse: Decodable {
    struct Model: Decodable, Identifiable, Hashable {
        let id: String
    }
    let data: [Model]
}
