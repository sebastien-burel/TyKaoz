import Foundation

/// One streaming event from Anthropic's `/v1/messages` SSE response.
/// Anthropic emits a structured sequence: message_start → one or more
/// content_block_start/delta/stop pairs → message_delta → message_stop.
/// The same event shape is shared across types; the `type` discriminator
/// tells us which fields are populated.
struct AnthropicStreamEvent: Decodable {
    let type: String
    let index: Int?
    let contentBlock: ContentBlock?
    let delta: Delta?

    struct ContentBlock: Decodable {
        let type: String          // "text" or "tool_use"
        let id: String?           // populated for tool_use
        let name: String?         // populated for tool_use
    }

    struct Delta: Decodable {
        let type: String?         // "text_delta", "input_json_delta", "stop_reason", ...
        let text: String?         // for text_delta
        let partialJSON: String?  // for input_json_delta

        enum CodingKeys: String, CodingKey {
            case type, text
            case partialJSON = "partial_json"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, index, delta
        case contentBlock = "content_block"
    }
}

struct AnthropicModelsResponse: Decodable {
    struct Model: Decodable, Identifiable, Hashable {
        let id: String
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }
    let data: [Model]
}
