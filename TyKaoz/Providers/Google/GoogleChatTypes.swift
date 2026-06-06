import Foundation

/// Models list response (used only for the Settings model picker; the chat
/// flow itself goes through JSONSerialization for both request and stream
/// parsing because Gemini's parts can mix text and functionCall objects).
struct GoogleModelsResponse: Decodable {
    struct Model: Decodable, Identifiable, Hashable {
        let name: String                            // "models/gemini-2.5-flash"
        let displayName: String?
        let supportedGenerationMethods: [String]?

        var id: String {
            name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
        }
    }
    let models: [Model]
}
