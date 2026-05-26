import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ChatSession {
    enum State: Equatable {
        case idle
        case streaming
        case failed(message: String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private var task: Task<Void, Never>?

    func send(
        text: String,
        in conversation: Binding<Conversation>,
        using provider: any LLMProvider
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state != .streaming else { return }

        conversation.wrappedValue.messages.append(Message(role: .user, content: trimmed))

        let assistant = Message(role: .assistant, content: "")
        let assistantID = assistant.id
        conversation.wrappedValue.messages.append(assistant)

        let history = conversation.wrappedValue.messages
            .dropLast()
            .compactMap { ChatMessage($0) }

        state = .streaming

        task = Task { [weak self] in
            do {
                for try await delta in provider.chat(messages: history) {
                    if Task.isCancelled { break }
                    guard let idx = conversation.wrappedValue.messages.firstIndex(where: { $0.id == assistantID }) else { break }
                    conversation.wrappedValue.messages[idx].content += delta
                }
                self?.state = .idle
            } catch is CancellationError {
                self?.state = .idle
            } catch let error as OllamaClientError {
                self?.state = .failed(message: error.errorDescription ?? "Erreur.")
            } catch let error as OpenAICompatibleError {
                self?.state = .failed(message: error.errorDescription ?? "Erreur.")
            } catch let error as AnthropicClientError {
                self?.state = .failed(message: error.errorDescription ?? "Erreur.")
            } catch let error as GoogleClientError {
                self?.state = .failed(message: error.errorDescription ?? "Erreur.")
            } catch {
                self?.state = .failed(message: error.localizedDescription)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
