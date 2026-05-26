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

    /// Defensive cap: a tool-using model occasionally goes in circles. After
    /// this many provider → tool → provider iterations we bail and let the
    /// user inspect what happened.
    static let maxToolRounds = 10

    private(set) var state: State = .idle

    @ObservationIgnored private var task: Task<Void, Never>?

    func send(
        text: String,
        in conversation: Binding<Conversation>,
        using provider: any LLMProvider,
        tools: ToolRegistry = ToolRegistry(tools: [])
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state != .streaming else { return }

        conversation.wrappedValue.messages.append(Message(role: .user, content: trimmed))
        state = .streaming

        task = Task { [weak self] in
            do {
                try await self?.runConversationLoop(in: conversation, provider: provider, tools: tools)
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

    // MARK: - Internals

    /// Multi-round loop: ask the provider for a turn, append text deltas to
    /// the current assistant message and collect any tool calls. If tool
    /// calls came back, execute them, append the toolCall + toolResult
    /// messages to the conversation, and loop. Otherwise we're done.
    private func runConversationLoop(
        in conversation: Binding<Conversation>,
        provider: any LLMProvider,
        tools: ToolRegistry
    ) async throws {
        for round in 0..<Self.maxToolRounds {
            if Task.isCancelled { return }

            // Fresh empty assistant message for this round's text output.
            let assistant = Message(role: .assistant, content: "")
            let assistantID = assistant.id
            conversation.wrappedValue.messages.append(assistant)

            let history = conversation.wrappedValue.messages
                .dropLast()
                .map { ChatMessage($0) }

            var pendingCalls: [(id: String, name: String, args: String, signature: String?)] = []

            for try await event in provider.chat(messages: Array(history), tools: tools.specs) {
                if Task.isCancelled { return }
                switch event {
                case .textDelta(let delta):
                    if let idx = conversation.wrappedValue.messages.firstIndex(where: { $0.id == assistantID }) {
                        conversation.wrappedValue.messages[idx].content += delta
                    }
                case .reasoningDelta(let delta):
                    if let idx = conversation.wrappedValue.messages.firstIndex(where: { $0.id == assistantID }) {
                        let previous = conversation.wrappedValue.messages[idx].reasoningContent ?? ""
                        conversation.wrappedValue.messages[idx].reasoningContent = previous + delta
                    }
                case .toolCall(let id, let name, let argumentsJSON, let signature):
                    pendingCalls.append((id, name, argumentsJSON, signature))
                }
            }

            // If the assistant produced no text AND no reasoning this round,
            // drop the empty placeholder — tool calls (if any) carry their
            // own UI cards. Keep it if reasoning_content is present: the
            // provider expects it back in the next round's history.
            if let idx = conversation.wrappedValue.messages.firstIndex(where: { $0.id == assistantID }),
               conversation.wrappedValue.messages[idx].content.isEmpty,
               (conversation.wrappedValue.messages[idx].reasoningContent ?? "").isEmpty {
                conversation.wrappedValue.messages.remove(at: idx)
            }

            if pendingCalls.isEmpty { return }

            // Append the tool_call entries first so the UI can show them.
            for call in pendingCalls {
                conversation.wrappedValue.messages.append(
                    Message(
                        role: .toolCall,
                        content: call.args,
                        toolCallID: call.id,
                        toolName: call.name,
                        thoughtSignature: call.signature
                    )
                )
            }

            // Execute the calls (one by one for determinism; could be a
            // task group if any tool becomes slow).
            for call in pendingCalls {
                if Task.isCancelled { return }
                let result = await tools.execute(
                    ToolCall(
                        id: call.id,
                        toolName: call.name,
                        arguments: Data(call.args.utf8)
                    )
                )
                conversation.wrappedValue.messages.append(
                    Message(
                        role: .toolResult,
                        content: result.content,
                        toolCallID: result.callID,
                        toolIsError: result.isError
                    )
                )
            }

            // Tail-safety: prevent infinite loops on degenerate models.
            if round == Self.maxToolRounds - 1 {
                conversation.wrappedValue.messages.append(
                    Message(
                        role: .assistant,
                        content: "[Limite de \(Self.maxToolRounds) tours d'outils atteinte — interrompu.]"
                    )
                )
            }
        }
    }
}
