import Foundation

/// Builds the active LLMProvider from current settings. Returns nil when the
/// current selection cannot be assembled (missing URL or model for Ollama).
enum ProviderFactory {
    static func make(from settings: AppSettings) -> (any LLMProvider)? {
        switch settings.selectedProviderID {
        case "apple":
            return AppleIntelligenceProvider()
        case "ollama":
            guard let url = settings.serverURL,
                  let model = settings.selectedModel,
                  !model.isEmpty
            else { return nil }
            return OllamaProvider(baseURL: url, model: model)
        default:
            return nil
        }
    }
}
