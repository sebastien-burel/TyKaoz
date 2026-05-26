import Foundation
import FoundationModels

struct AppleIntelligenceProvider: LLMProvider {
    let id: String = "apple"
    let displayName: String = "Apple Intelligence"

    /// Synchronous convenience for UI hints (e.g. sidebar indicator).
    /// The full `availability()` returns the precise reason of unavailability.
    static var isReady: Bool {
        SystemLanguageModel.default.isAvailable
    }

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

    func chat(messages: [ChatMessage], tools: [ToolSpec]) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let lastUserIdx = messages.lastIndex(where: { $0.role == .user }) else {
                        throw AppleIntelligenceError.noUserMessage
                    }
                    let priorHistory = Array(messages[..<lastUserIdx])
                    let lastUser = messages[lastUserIdx]

                    let transcript = Self.buildTranscript(
                        systemPrompt: Self.defaultInstructions,
                        history: priorHistory
                    )
                    let session = LanguageModelSession(transcript: transcript)

                    var emitted = 0
                    let stream = session.streamResponse(to: lastUser.content)
                    for try await snapshot in stream {
                        if Task.isCancelled { break }
                        let text = snapshot.content
                        if text.count > emitted {
                            let startIndex = text.index(text.startIndex, offsetBy: emitted)
                            let delta = String(text[startIndex...])
                            emitted = text.count
                            continuation.yield(.textDelta(delta))
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

    // MARK: - Transcript construction

    private static let defaultInstructions =
        "Tu es un assistant utile. Réponds clairement et en français par défaut."

    private static func buildTranscript(
        systemPrompt: String,
        history: [ChatMessage]
    ) -> Transcript {
        var entries: [Transcript.Entry] = []

        entries.append(.instructions(
            Transcript.Instructions(
                id: UUID().uuidString,
                segments: [.text(textSegment(systemPrompt))],
                toolDefinitions: []
            )
        ))

        for message in history {
            let segment: Transcript.Segment = .text(textSegment(message.content))
            switch message.role {
            case .user:
                entries.append(.prompt(
                    Transcript.Prompt(
                        id: UUID().uuidString,
                        segments: [segment],
                        options: GenerationOptions(),
                        responseFormat: nil
                    )
                ))
            case .assistant:
                entries.append(.response(
                    Transcript.Response(
                        id: UUID().uuidString,
                        assetIDs: [],
                        segments: [segment]
                    )
                ))
            case .system:
                entries.append(.instructions(
                    Transcript.Instructions(
                        id: UUID().uuidString,
                        segments: [segment],
                        toolDefinitions: []
                    )
                ))
            case .toolCall, .toolResult:
                // Foundation Models has its own Tool protocol — Bloc 4c will
                // bridge our ToolCall/ToolResult into Transcript.toolCalls /
                // .toolOutput entries. For now we drop them.
                continue
            }
        }

        return Transcript(entries: entries)
    }

    private static func textSegment(_ content: String) -> Transcript.TextSegment {
        Transcript.TextSegment(id: UUID().uuidString, content: content)
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
