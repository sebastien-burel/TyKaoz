import Foundation

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

        case "mistral":
            guard !settings.mistralAPIKey.isEmpty,
                  let model = settings.mistralModel,
                  !model.isEmpty
            else { return nil }
            return MistralProvider(apiKey: settings.mistralAPIKey, model: model)

        default:
            return nil
        }
    }
}
