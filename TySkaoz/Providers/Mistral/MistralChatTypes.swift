import Foundation

struct MistralChatMessage: Codable, Hashable {
    let role: String
    let content: String
}

struct MistralChatRequest: Encodable {
    let model: String
    let messages: [MistralChatMessage]
    let stream: Bool
}

/// One streamed chunk from Mistral. The schema is OpenAI-compatible:
/// `choices[0].delta.content` is the delta, `finish_reason` is non-nil on
/// the last chunk.
struct MistralChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
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

struct MistralModelsResponse: Decodable {
    struct Model: Decodable, Identifiable, Hashable {
        let id: String
    }
    let data: [Model]
}
