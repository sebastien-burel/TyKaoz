import Foundation

/// Pure heuristic that flags model IDs likely to be chat-capable, used to
/// hide embedding / moderation / OCR / TTS variants from the curation list by
/// default. Users can always toggle "Tout afficher" to bypass.
enum ModelHeuristic {

    static func isLikelyChatModel(id: String, provider: ProviderID) -> Bool {
        let lower = id.lowercased()
        switch provider {
        case .ollama, .mistral, .openai, .anthropic, .deepseek:
            return !nonChatHints.contains(where: lower.contains)
        case .apple:
            return true
        }
    }

    /// Substrings commonly found in non-chat model IDs across providers.
    private static let nonChatHints: [String] = [
        "embed",
        "embedding",
        "moderation",
        "ocr",
        "whisper",
        "tts",
        "speech",
        "image",
        "dall-e",
        "audio"
    ]
}
