import Foundation

/// Shared OpenAI-compatible chat completion schema. Reused by Mistral,
/// OpenAI, DeepSeek (and any future provider that exposes the same wire
/// format).

struct OpenAICompatibleMessage: Codable, Hashable {
    let role: String
    let content: String
}

struct OpenAICompatibleRequest: Encodable {
    let model: String
    let messages: [OpenAICompatibleMessage]
    let stream: Bool
}

/// One streamed chunk. `choices[0].delta.content` carries the delta;
/// `finish_reason` is non-nil on the final chunk.
struct OpenAICompatibleChunk: Decodable {
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

struct OpenAICompatibleModelsResponse: Decodable {
    struct Model: Decodable, Identifiable, Hashable {
        let id: String
    }
    let data: [Model]
}
