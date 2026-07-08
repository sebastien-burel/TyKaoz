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

        /// Optional: some providers (e.g. Qwen reasoning models) emit
        /// choices with no `delta` on certain chunks. A missing delta must
        /// not abort the whole stream.
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    /// Token accounting. Present only when the request opts in via
    /// `stream_options.include_usage`; it then arrives in a trailing chunk
    /// (with `choices` empty) just before `[DONE]`. Some servers also inline
    /// it on the final content chunk.
    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }

    /// Optional: a trailing usage-only chunk, or an occasional metadata
    /// chunk, can arrive without any `choices` key. Decode it as empty
    /// rather than throwing.
    let choices: [Choice]?
    let usage: Usage?
}

struct OpenAICompatibleModelsResponse: Decodable {
    struct Model: Decodable, Identifiable, Hashable {
        let id: String
    }
    let data: [Model]
}
