import Foundation
import FoundationModels

struct AppleIntelligenceProvider: LLMProvider {
    let id: String = "apple"
    let displayName: String = "Apple Intelligence"

    func availability() async -> ProviderAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "Cet appareil ne prend pas en charge Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Activez Apple Intelligence dans les Réglages système.")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "Le modèle Apple Intelligence se télécharge ou n'est pas prêt.")
        case .unavailable(let other):
            return .unavailable(reason: "Indisponible : \(other).")
        }
    }

    func chat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Split last user message from prior history. If for some
                    // reason there's no user message at the end (defensive),
                    // bail with a clear error.
                    guard let lastUser = messages.last(where: { $0.role == .user }) else {
                        throw AppleIntelligenceError.noUserMessage
                    }
                    let history = Array(messages.prefix(upTo: messages.lastIndex(where: { $0.role == .user })!))

                    let session = LanguageModelSession(
                        instructions: Self.buildInstructions(history: history)
                    )

                    var emitted = 0
                    let stream = session.streamResponse(to: lastUser.content)
                    for try await snapshot in stream {
                        if Task.isCancelled { break }
                        let text = snapshot.content
                        if text.count > emitted {
                            let startIndex = text.index(text.startIndex, offsetBy: emitted)
                            let delta = String(text[startIndex...])
                            emitted = text.count
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Builds an `Instructions` value that replays prior turns. For Phase 5 we
    /// embed the history textually; a future iteration may switch to a real
    /// `Transcript` for cleaner semantics.
    private static func buildInstructions(history: [ChatMessage]) -> Instructions {
        if history.isEmpty {
            return Instructions("Tu es un assistant utile. Réponds clairement et en français par défaut.")
        }
        var lines: [String] = [
            "Tu es un assistant utile. Réponds clairement et en français par défaut.",
            "Voici l'historique de la conversation jusqu'ici :"
        ]
        for message in history {
            let prefix: String
            switch message.role {
            case .user:      prefix = "Utilisateur"
            case .assistant: prefix = "Assistant"
            case .system:    prefix = "Système"
            }
            lines.append("\(prefix) : \(message.content)")
        }
        return Instructions(lines.joined(separator: "\n"))
    }
}

enum AppleIntelligenceError: Error, LocalizedError {
    case noUserMessage

    var errorDescription: String? {
        switch self {
        case .noUserMessage:
            return "Aucun message utilisateur à envoyer."
        }
    }
}
