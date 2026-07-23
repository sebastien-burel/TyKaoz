import Foundation
import KaozKit
import KaozMLX

enum ProviderFactory {
    /// The run's default provider (the one selected in Settings).
    @MainActor
    static func make(
        from settings: AppSettings,
        tools: ToolRegistry = ToolRegistry(tools: [])
    ) -> (any LLMProvider)? {
        // ComfyUI is an image provider with main-actor-only config (workflows) —
        // not chat, not JS-selectable, so it stays out of the resolver.
        if settings.selectedProviderID == "comfyui" {
            guard let url = settings.comfyuiBaseURL,
                  let name = settings.comfyuiModel,
                  let json = settings.comfyuiWorkflows[name], !json.isEmpty
            else { return nil }
            return ComfyUIProvider(
                baseURL: url, apiKey: settings.comfyuiAPIKey,
                workflowName: name, workflowJSON: json,
                params: settings.comfyuiParams(for: name))
        }
        return resolver(from: settings, tools: tools)(settings.selectedProviderID, [:])
    }

    /// Providers an agent may name from JS via `host.providers()` — the
    /// chat-capable ids (ComfyUI is image-only, excluded).
    @MainActor
    static func catalog(from settings: AppSettings) -> [ProviderDescriptor] {
        // `model` = the provider's configured default, so an agent can
        // instantiate an element directly (host.provider(id, {model})).
        [
            .init(id: "anthropic", name: "Anthropic", model: settings.anthropicModel),
            .init(id: "openai", name: "OpenAI", model: settings.openaiModel),
            .init(id: "google", name: "Google Gemini", model: settings.googleModel),
            .init(id: "mistral", name: "Mistral", model: settings.mistralModel),
            .init(id: "deepseek", name: "DeepSeek", model: settings.deepseekModel),
            .init(id: "qwen", name: "Qwen", model: settings.qwenModel),
            .init(id: "zai", name: "Z.AI", model: settings.zaiModel),
            .init(id: "kimi", name: "Kimi K3", model: settings.kimiModel),
            .init(id: "localOpenAI", name: "Serveur local", model: settings.localOpenAIModel),
            .init(id: "ollama", name: "Ollama", model: settings.selectedModel),
            .init(id: "apple", name: "Apple Intelligence"),
            .init(id: "mlx", name: "MLX", model: settings.mlxChatModelID),
        ]
    }

    /// Build a Sendable resolver that maps a provider `id` (+ JS `options`, e.g.
    /// `model`) to a provider. Runs off the main actor (an agent picks a provider
    /// mid-run), so it captures a snapshot of the settings up front; API keys stay
    /// here, never in JS. `make` is just `resolver(...)(selectedID, [:])`.
    @MainActor
    static func resolver(
        from settings: AppSettings,
        tools: ToolRegistry = ToolRegistry(tools: [])
    ) -> @Sendable (_ id: String, _ options: [String: Any]) -> (any LLMProvider)? {
        // Snapshot everything the resolver needs (it runs off the main actor).
        let useJS = settings.useJSProviders
        let anthropicKey = settings.anthropicAPIKey, anthropicModel = settings.anthropicModel
        let openaiKey = settings.openaiAPIKey, openaiModel = settings.openaiModel
        let googleKey = settings.googleAPIKey, googleModel = settings.googleModel
        let mistralKey = settings.mistralAPIKey, mistralModel = settings.mistralModel
        let deepseekKey = settings.deepseekAPIKey, deepseekModel = settings.deepseekModel
        let qwenKey = settings.qwenAPIKey, qwenModel = settings.qwenModel
        let zaiKey = settings.zaiAPIKey, zaiModel = settings.zaiModel
        let kimiKey = settings.kimiAPIKey, kimiModel = settings.kimiModel
        let localURL = settings.localOpenAIBaseURL, localKey = settings.localOpenAIAPIKey
        let localModel = settings.localOpenAIModel
        let ollamaURL = settings.serverURL, ollamaModel = settings.selectedModel
        let mlxModel = settings.mlxChatModelID

        return { id, options in
            let m = options["model"] as? String
            switch id {
            case "anthropic":
                let model = m ?? anthropicModel
                guard !anthropicKey.isEmpty, let model, !model.isEmpty else { return nil }
                return useJS
                    ? JSProviders.anthropic(apiKey: anthropicKey, model: model)
                    : AnthropicProvider(apiKey: anthropicKey, model: model)

            case "openai":
                let model = m ?? openaiModel
                guard !openaiKey.isEmpty, let model, !model.isEmpty else { return nil }
                return useJS
                    ? JSProviders.openai(apiKey: openaiKey, model: model)
                    : OpenAIProvider(apiKey: openaiKey, model: model)

            case "google":
                let model = m ?? googleModel
                guard !googleKey.isEmpty, let model, !model.isEmpty else { return nil }
                return useJS
                    ? JSProviders.google(apiKey: googleKey, model: model)
                    : GoogleProvider(apiKey: googleKey, model: model)

            case "mistral":
                let model = m ?? mistralModel
                guard !mistralKey.isEmpty, let model, !model.isEmpty else { return nil }
                return useJS
                    ? JSProviders.openaiCompatible(
                        id: "mistral-js", displayName: "Mistral (JS)",
                        apiKey: mistralKey, model: model,
                        baseURL: MistralProvider.baseURL.absoluteString)
                    : MistralProvider(apiKey: mistralKey, model: model)

            case "deepseek":
                let model = m ?? deepseekModel
                guard !deepseekKey.isEmpty, let model, !model.isEmpty else { return nil }
                return useJS
                    ? JSProviders.openaiCompatible(
                        id: "deepseek-js", displayName: "DeepSeek (JS)",
                        apiKey: deepseekKey, model: model,
                        baseURL: DeepSeekProvider.baseURL.absoluteString)
                    : DeepSeekProvider(apiKey: deepseekKey, model: model)

            case "qwen":
                let model = m ?? qwenModel
                guard !qwenKey.isEmpty, let model, !model.isEmpty else { return nil }
                return useJS
                    ? JSProviders.openaiCompatible(
                        id: "qwen-js", displayName: "Qwen (JS)",
                        apiKey: qwenKey, model: model,
                        baseURL: QwenProvider.baseURL.absoluteString)
                    : QwenProvider(apiKey: qwenKey, model: model)

            case "zai":
                let model = m ?? zaiModel
                guard !zaiKey.isEmpty, let model, !model.isEmpty else { return nil }
                return useJS
                    ? JSProviders.openaiCompatible(
                        id: "zai-js", displayName: "Z.AI (JS)",
                        apiKey: zaiKey, model: model,
                        baseURL: ZAIProvider.baseURL.absoluteString)
                    : ZAIProvider(apiKey: zaiKey, model: model)

            case "kimi":
                // OpenAI-compatible — JS-only (no Swift Kimi provider).
                let model = m ?? kimiModel
                guard !kimiKey.isEmpty, let model, !model.isEmpty else { return nil }
                return JSProviders.kimi(apiKey: kimiKey, model: model)

            case "localOpenAI":
                let model = m ?? localModel
                guard let url = localURL, let model, !model.isEmpty else { return nil }
                return useJS
                    ? JSProviders.openaiCompatible(
                        id: "localOpenAI-js", displayName: "Serveur local (JS)",
                        apiKey: localKey, model: model,
                        baseURL: LocalOpenAIProvider.normalize(url).absoluteString)
                    : LocalOpenAIProvider(baseURL: url, apiKey: localKey, model: model)

            case "ollama":
                let model = m ?? ollamaModel
                guard let url = ollamaURL, let model, !model.isEmpty else { return nil }
                return useJS
                    ? JSProviders.ollama(model: model, baseURL: url.absoluteString)
                    : OllamaProvider(baseURL: url, model: model)

            case "apple":
                return AppleIntelligenceProvider(toolRegistry: tools)

            case "mlx":
                guard let modelID = m ?? mlxModel, !modelID.isEmpty else { return nil }
                return MLXLLMProvider(modelID: modelID)

            default:
                return nil
            }
        }
    }
}
