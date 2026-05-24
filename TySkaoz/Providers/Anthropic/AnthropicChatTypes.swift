import Foundation

struct AnthropicMessage: Codable, Hashable {
    let role: String      // "user" or "assistant"
    let content: String
}

struct AnthropicChatRequest: Encodable {
    let model: String
    let messages: [AnthropicMessage]
    let system: String?
    let stream: Bool
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, system, stream
        case maxTokens = "max_tokens"
    }
}

/// One `data:` payload from the streamed events. We use a discriminator on
/// `type` to know which kind of event we're looking at.
struct AnthropicStreamEvent: Decodable {
    let type: String
    let delta: Delta?

    struct Delta: Decodable {
        let type: String?
        let text: String?
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
