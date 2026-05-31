import Foundation

/// Zhipu AI's z.ai gateway hosts the GLM family (GLM-4, GLM-4.5, GLM-4-Plus,
/// etc.) behind an OpenAI-compatible endpoint. The China-mainland service at
/// `open.bigmodel.cn` uses their own request format; this provider targets
/// only the international `api.z.ai` host.
struct ZAIProvider: LLMProvider {
    let id: String = "zai"
    let displayName: String = "z.ai"

    let apiKey: String
    let model: String

    private let client: OpenAICompatibleClient

    static let baseURL = URL(string: "https://api.z.ai/api/paas/v4")!

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.client = OpenAICompatibleClient(baseURL: Self.baseURL, apiKey: apiKey, session: session)
    }

    func availability() async -> ProviderAvailability {
        guard !apiKey.isEmpty else {
            return .unavailable(reason: "Renseignez votre clé API z.ai dans les réglages.")
        }
        do {
            let models = try await client.listModels()
            guard models.contains(where: { $0.id == model }) else {
                return .unavailable(reason: "Le modèle « \(model) » n'est pas accessible avec cette clé.")
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
