import Foundation

struct MistralProvider: LLMProvider {
    let id: String = "mistral"
    let displayName: String = "Mistral"

    let apiKey: String
    let model: String

    private let client: MistralClient

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.client = MistralClient(apiKey: apiKey, session: session)
    }

    func availability() async -> ProviderAvailability {
        guard !apiKey.isEmpty else {
            return .unavailable(reason: "Renseignez votre clé API Mistral dans les réglages.")
        }
        do {
            let models = try await client.listModels()
            guard models.contains(where: { $0.id == model }) else {
                return .unavailable(reason: "Le modèle « \(model) » n'est pas accessible avec cette clé.")
            }
            return .ready
        } catch let error as MistralClientError {
            return .unavailable(reason: error.errorDescription ?? "Erreur.")
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    func chat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        let mistralMessages = messages.map { MistralChatMessage(role: $0.role.rawValue, content: $0.content) }
        return client.chat(model: model, messages: mistralMessages)
    }
}
