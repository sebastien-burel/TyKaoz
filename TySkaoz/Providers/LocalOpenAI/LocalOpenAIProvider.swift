import Foundation

/// Generic OpenAI-compatible provider for self-hosted inference servers:
/// vLLM, LM Studio, llama.cpp's `server`, etc. The user supplies the
/// base URL (and optionally an API key) in the settings panel; the
/// model list comes from `/v1/models` like any cloud OpenAI host.
struct LocalOpenAIProvider: LLMProvider {
    let id: String = "localOpenAI"
    let displayName: String = "Local OpenAI"

    let baseURL: URL
    let apiKey: String
    let model: String

    private let client: OpenAICompatibleClient

    init(baseURL: URL, apiKey: String, model: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.client = OpenAICompatibleClient(baseURL: baseURL, apiKey: apiKey, session: session)
    }

    func availability() async -> ProviderAvailability {
        // No key required for most local servers (vLLM/LM Studio/llama.cpp
        // default to no auth). Reachability check below catches a typo
        // in the URL.
        do {
            let models = try await client.listModels()
            guard models.contains(where: { $0.id == model }) else {
                return .unavailable(
                    reason: "Le modèle « \(model) » n'est pas servi par ce serveur."
                )
            }
            return .ready
        } catch let error as OpenAICompatibleError {
            return .unavailable(reason: error.errorDescription ?? "Erreur.")
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    func chat(messages: [ChatMessage], tools: [ToolSpec]) -> AsyncThrowingStream<StreamEvent, Error> {
        client.chat(model: model, messages: messages, tools: tools)
    }
}
