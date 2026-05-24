import Foundation

struct GooglePart: Codable, Hashable {
    let text: String
}

struct GoogleContent: Codable, Hashable {
    let role: String?       // "user" or "model"; omitted for systemInstruction
    let parts: [GooglePart]
}

struct GoogleChatRequest: Encodable {
    let contents: [GoogleContent]
    let systemInstruction: GoogleContent?
}

/// One streamed `data:` payload. The interesting bit is
/// candidates[0].content.parts[0].text plus an optional finishReason.
struct GoogleStreamChunk: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            let parts: [GooglePart]?
            let role: String?
        }
        let content: Content?
        let finishReason: String?
    }
    let candidates: [Candidate]?
}

struct GoogleModelsResponse: Decodable {
    struct Model: Decodable, Identifiable, Hashable {
        let name: String                            // "models/gemini-2.5-flash"
        let displayName: String?
        let supportedGenerationMethods: [String]?

        var id: String {
            // Strip the "models/" prefix for storage; we add it back when
            // building chat URLs.
            name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
        }
    }
    let models: [Model]
}
