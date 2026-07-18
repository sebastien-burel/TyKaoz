import Foundation
import TyKaozKit

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
            if settings.useJSProviders {
                return JSProviders.anthropic(apiKey: settings.anthropicAPIKey, model: model)
            }
            return AnthropicProvider(apiKey: settings.anthropicAPIKey, model: model)

        case "apple":
            return AppleIntelligenceProvider(toolRegistry: tools)

        case "comfyui":
            guard let url = settings.comfyuiBaseURL,
                  let name = settings.comfyuiModel,
                  let json = settings.comfyuiWorkflows[name],
                  !json.isEmpty
            else { return nil }
            return ComfyUIProvider(
                baseURL: url,
                apiKey: settings.comfyuiAPIKey,
                workflowName: name,
                workflowJSON: json,
                params: settings.comfyuiParams(for: name)
            )

        case "deepseek":
            guard !settings.deepseekAPIKey.isEmpty,
                  let model = settings.deepseekModel,
                  !model.isEmpty
            else { return nil }
            if settings.useJSProviders {
                return JSProviders.openaiCompatible(
                    id: "deepseek-js", displayName: "DeepSeek (JS)",
                    apiKey: settings.deepseekAPIKey, model: model,
                    baseURL: DeepSeekProvider.baseURL.absoluteString)
            }
            return DeepSeekProvider(apiKey: settings.deepseekAPIKey, model: model)

        case "google":
            guard !settings.googleAPIKey.isEmpty,
                  let model = settings.googleModel,
                  !model.isEmpty
            else { return nil }
            return GoogleProvider(apiKey: settings.googleAPIKey, model: model)

        case "localOpenAI":
            guard let url = settings.localOpenAIBaseURL,
                  let model = settings.localOpenAIModel,
                  !model.isEmpty
            else { return nil }
            if settings.useJSProviders {
                return JSProviders.openaiCompatible(
                    id: "localOpenAI-js", displayName: "Serveur local (JS)",
                    apiKey: settings.localOpenAIAPIKey, model: model,
                    baseURL: LocalOpenAIProvider.normalize(url).absoluteString)
            }
            return LocalOpenAIProvider(
                baseURL: url,
                apiKey: settings.localOpenAIAPIKey,
                model: model
            )

        case "mlx":
            guard let modelID = settings.mlxChatModelID,
                  !modelID.isEmpty
            else { return nil }
            return MLXLLMProvider(modelID: modelID)

        case "mistral":
            guard !settings.mistralAPIKey.isEmpty,
                  let model = settings.mistralModel,
                  !model.isEmpty
            else { return nil }
            if settings.useJSProviders {
                return JSProviders.openaiCompatible(
                    id: "mistral-js", displayName: "Mistral (JS)",
                    apiKey: settings.mistralAPIKey, model: model,
                    baseURL: MistralProvider.baseURL.absoluteString)
            }
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
            if settings.useJSProviders {
                return JSProviders.openai(apiKey: settings.openaiAPIKey, model: model)
            }
            return OpenAIProvider(apiKey: settings.openaiAPIKey, model: model)

        case "qwen":
            guard !settings.qwenAPIKey.isEmpty,
                  let model = settings.qwenModel,
                  !model.isEmpty
            else { return nil }
            if settings.useJSProviders {
                return JSProviders.openaiCompatible(
                    id: "qwen-js", displayName: "Qwen (JS)",
                    apiKey: settings.qwenAPIKey, model: model,
                    baseURL: QwenProvider.baseURL.absoluteString)
            }
            return QwenProvider(apiKey: settings.qwenAPIKey, model: model)

        case "zai":
            guard !settings.zaiAPIKey.isEmpty,
                  let model = settings.zaiModel,
                  !model.isEmpty
            else { return nil }
            if settings.useJSProviders {
                return JSProviders.openaiCompatible(
                    id: "zai-js", displayName: "Z.AI (JS)",
                    apiKey: settings.zaiAPIKey, model: model,
                    baseURL: ZAIProvider.baseURL.absoluteString)
            }
            return ZAIProvider(apiKey: settings.zaiAPIKey, model: model)

        default:
            return nil
        }
    }
}
