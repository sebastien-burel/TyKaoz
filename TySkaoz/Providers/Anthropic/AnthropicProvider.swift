import Foundation

struct AnthropicProvider: LLMProvider {
    let id: String = "anthropic"
    let displayName: String = "Anthropic"

    let apiKey: String
    let model: String

    private let client: AnthropicClient

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.client = AnthropicClient(apiKey: apiKey, session: session)
    }

    func availability() async -> ProviderAvailability {
        guard !apiKey.isEmpty else {
            return .unavailable(reason: "Renseignez votre clé API Anthropic dans les réglages.")
        }
        do {
            let models = try await client.listModels()
            guard models.contains(where: { $0.id == model }) else {
                return .unavailable(reason: "Le modèle « \(model) » n'est pas accessible avec cette clé.")
            }
            return .ready
        } catch let error as AnthropicClientError {
            return .unavailable(reason: error.errorDescription ?? "Erreur.")
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    func chat(messages: [ChatMessage], tools: [ToolSpec]) -> AsyncThrowingStream<StreamEvent, Error> {
        // Extract system messages into a single concatenated system prompt;
        // Anthropic wants them as a top-level parameter, not in the array.
        let systemBits = messages.filter { $0.role == .system }.map(\.content)
        let system = systemBits.isEmpty ? nil : systemBits.joined(separator: "\n\n")

        let anthropicMessages = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .map { AnthropicMessage(role: $0.role.rawValue, content: $0.content) }

        return wrapAsTextStream(client.chat(model: model, system: system, messages: anthropicMessages))
    }
}
