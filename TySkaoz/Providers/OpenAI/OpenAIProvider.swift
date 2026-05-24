import Foundation

struct OpenAIProvider: LLMProvider {
    let id: String = "openai"
    let displayName: String = "OpenAI"

    let apiKey: String
    let model: String

    private let client: OpenAICompatibleClient

    static let baseURL = URL(string: "https://api.openai.com/v1")!

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.client = OpenAICompatibleClient(baseURL: Self.baseURL, apiKey: apiKey, session: session)
    }

    func availability() async -> ProviderAvailability {
        guard !apiKey.isEmpty else {
            return .unavailable(reason: "Renseignez votre clé API OpenAI dans les réglages.")
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

    func chat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        let mapped = messages.map { OpenAICompatibleMessage(role: $0.role.rawValue, content: $0.content) }
        return client.chat(model: model, messages: mapped)
    }
}
