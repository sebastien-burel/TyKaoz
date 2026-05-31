import Foundation

enum ProviderFactory {
    static func make(
        from settings: AppSettings,
        tools: ToolRegistry = ToolRegistry(tools: [])
    ) -> (any LLMProvider)? {
        switch settings.selectedProviderID {
        case "anthropic":
            guard !settings.anthropicAPIKey.isEmpty,
                  let model = settings.anthropicModel,
                  !model.isEmpty
            else { return nil }
            return AnthropicProvider(apiKey: settings.anthropicAPIKey, model: model)

        case "apple":
            return AppleIntelligenceProvider(toolRegistry: tools)

        case "deepseek":
            guard !settings.deepseekAPIKey.isEmpty,
                  let model = settings.deepseekModel,
                  !model.isEmpty
            else { return nil }
            return DeepSeekProvider(apiKey: settings.deepseekAPIKey, model: model)

        case "google":
            guard !settings.googleAPIKey.isEmpty,
                  let model = settings.googleModel,
                  !model.isEmpty
            else { return nil }
            return GoogleProvider(apiKey: settings.googleAPIKey, model: model)

        case "mistral":
            guard !settings.mistralAPIKey.isEmpty,
                  let model = settings.mistralModel,
                  !model.isEmpty
            else { return nil }
            return MistralProvider(apiKey: settings.mistralAPIKey, model: model)

        case "ollama":
            guard let url = settings.serverURL,
                  let model = settings.selectedModel,
                  !model.isEmpty
            else { return nil }
            return OllamaProvider(baseURL: url, model: model)

        case "openai":
            guard !settings.openaiAPIKey.isEmpty,
                  let model = settings.openaiModel,
                  !model.isEmpty
            else { return nil }
            return OpenAIProvider(apiKey: settings.openaiAPIKey, model: model)

        case "qwen":
            guard !settings.qwenAPIKey.isEmpty,
                  let model = settings.qwenModel,
                  !model.isEmpty
            else { return nil }
            return QwenProvider(apiKey: settings.qwenAPIKey, model: model)

        case "zai":
            guard !settings.zaiAPIKey.isEmpty,
                  let model = settings.zaiModel,
                  !model.isEmpty
            else { return nil }
            return ZAIProvider(apiKey: settings.zaiAPIKey, model: model)

        default:
            return nil
        }
    }
}
