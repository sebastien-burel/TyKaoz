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

    typealias ChatStreamProvider = (URL, String, [OllamaChatMessage]) -> AsyncThrowingStream<String, Error>

    private(set) var state: State = .idle

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let chatStream: ChatStreamProvider

    init(chatStream: @escaping ChatStreamProvider = { baseURL, model, messages in
        OllamaClient(baseURL: baseURL).chat(model: model, messages: messages)
    }) {
        self.chatStream = chatStream
    }

    func send(
        text: String,
        in conversation: Binding<Conversation>,
        model: String,
        baseURL: URL
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state != .streaming else { return }

        conversation.wrappedValue.messages.append(Message(role: .user, content: trimmed))

        let assistant = Message(role: .assistant, content: "")
        let assistantID = assistant.id
        conversation.wrappedValue.messages.append(assistant)

        let history = conversation.wrappedValue.messages
            .dropLast()
            .map { OllamaChatMessage(role: $0.role.rawValue, content: $0.content) }

        let stream = chatStream(baseURL, model, history)
        state = .streaming

        task = Task { [weak self] in
            do {
                for try await delta in stream {
                    if Task.isCancelled { break }
                    guard let idx = conversation.wrappedValue.messages.firstIndex(where: { $0.id == assistantID }) else { break }
                    conversation.wrappedValue.messages[idx].content += delta
                }
                self?.state = .idle
            } catch is CancellationError {
                self?.state = .idle
            } catch let error as OllamaClientError {
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
