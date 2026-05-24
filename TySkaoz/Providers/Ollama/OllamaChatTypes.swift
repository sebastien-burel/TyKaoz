import Foundation

struct OllamaChatMessage: Codable, Hashable {
    let role: String
    let content: String
}

struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
}

struct OllamaChatChunk: Decodable {
    let message: OllamaChatMessage
    let done: Bool
}
