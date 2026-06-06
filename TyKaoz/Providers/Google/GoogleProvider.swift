import Foundation

struct GoogleProvider: LLMProvider {
    let id: String = "google"
    let displayName: String = "Google Gemini"

    let apiKey: String
    let model: String

    private let client: GoogleClient

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.client = GoogleClient(apiKey: apiKey, session: session)
    }

    func availability() async -> ProviderAvailability {
        guard !apiKey.isEmpty else {
            return .unavailable(reason: "Renseignez votre clé API Google AI Studio dans les réglages.")
        }
        do {
            let models = try await client.listModels()
            guard models.contains(where: { $0.id == model }) else {
                return .unavailable(reason: "Le modèle « \(model) » n'est pas accessible avec cette clé.")
            }
            return .ready
        } catch let error as GoogleClientError {
            return .unavailable(reason: error.errorDescription ?? "Erreur.")
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    func chat(messages: [ChatMessage], tools: [ToolSpec]) -> AsyncThrowingStream<StreamEvent, Error> {
        client.chat(model: model, messages: messages, tools: tools)
    }
}
