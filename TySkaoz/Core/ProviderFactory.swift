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

        case "openai":
            guard !settings.openaiAPIKey.isEmpty,
                  let model = settings.openaiModel,
                  !model.isEmpty
            else { return nil }
            return OpenAIProvider(apiKey: settings.openaiAPIKey, model: model)

        case "deepseek":
            guard !settings.deepseekAPIKey.isEmpty,
                  let model = settings.deepseekModel,
                  !model.isEmpty
            else { return nil }
            return DeepSeekProvider(apiKey: settings.deepseekAPIKey, model: model)

        default:
            return nil
        }
    }
}
