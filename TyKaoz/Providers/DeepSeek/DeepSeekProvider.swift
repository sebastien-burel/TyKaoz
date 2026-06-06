import Foundation

struct DeepSeekProvider: LLMProvider {
    let id: String = "deepseek"
    let displayName: String = "DeepSeek"

    let apiKey: String
    let model: String

    private let client: OpenAICompatibleClient

    static let baseURL = URL(string: "https://api.deepseek.com/v1")!

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.client = OpenAICompatibleClient(baseURL: Self.baseURL, apiKey: apiKey, session: session)
    }

    func availability() async -> ProviderAvailability {
        guard !apiKey.isEmpty else {
            return .unavailable(reason: "Renseignez votre clé API DeepSeek dans les réglages.")
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
