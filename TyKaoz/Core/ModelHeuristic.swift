import Foundation

/// Pure heuristic that flags model IDs likely to be chat-capable, used to
/// hide embedding / moderation / OCR / TTS variants from the curation list by
/// default. Users can always toggle "Tout afficher" to bypass.
enum ModelHeuristic {

    static func isLikelyChatModel(id: String, provider: ProviderID) -> Bool {
        let lower = id.lowercased()
        // Gemini image-generation models (e.g. gemini-2.5-flash-image) run
        // through the normal chat `generateContent` endpoint, so they're
        // usable here despite the "image" substring. Imagen / DALL·E (their
        // own `predict`/images endpoints) stay hidden.
        if provider == .google, lower.contains("gemini"), lower.contains("image") {
            return true
        }
        // OpenAI image-generation models (gpt-image-1, dall-e) are usable
        // via the Images API in the chat view.
        if provider == .openai, lower.contains("gpt-image") || lower.contains("dall-e") {
            return true
        }
        // Qwen text-to-image models (DashScope native endpoint).
        if provider == .qwen, lower.contains("qwen-image") || lower.hasPrefix("wan") {
            return true
        }
        // z.ai CogView text-to-image models (OpenAI-style images endpoint).
        if provider == .zai, lower.contains("cogview") {
            return true
        }
        switch provider {
        case .ollama, .mistral, .openai, .anthropic, .google, .deepseek, .qwen, .zai, .localOpenAI, .mlx:
            return !nonChatHints.contains(where: lower.contains)
        case .apple, .comfyui:
            // Apple has one model; ComfyUI "models" are user-named workflows —
            // neither is filtered by the id heuristic.
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
