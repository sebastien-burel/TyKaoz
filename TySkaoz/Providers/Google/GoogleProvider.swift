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
        // System messages are concatenated into systemInstruction; the rest
        // becomes contents[] with role "user" or "model" (Google uses "model"
        // for assistant turns).
        let systemBits = messages.filter { $0.role == .system }.map(\.content)
        let system = systemBits.isEmpty ? nil : systemBits.joined(separator: "\n\n")

        let contents: [GoogleContent] = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .map { message in
                let role = (message.role == .assistant) ? "model" : "user"
                return GoogleContent(role: role, parts: [GooglePart(text: message.content)])
            }

        return wrapAsTextStream(client.chat(model: model, system: system, contents: contents))
    }
}
