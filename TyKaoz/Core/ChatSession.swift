import Foundation
import TyKaozKit
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
    /// user inspect what happened. Sized for wiki curation, where a single
    /// ingest legitimately reads a source then writes several pages — each
    /// its own round — so a low cap would truncate honest work.
    static let maxToolRounds = 20

    private(set) var state: State = .idle

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Set per-send so the conversation loop can resolve attachment file
    /// URLs while building provider history. nil = no attachments in play.
    @ObservationIgnored private var store: ConversationStore?

    func send(
        text: String,
        in conversation: Binding<Conversation>,
        using provider: any LLMProvider,
        tools: ToolRegistry = ToolRegistry(tools: []),
        memoryContext: String? = nil,
        attachments: [Message.Attachment] = [],
        model: String? = nil,
        store: ConversationStore? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty, state != .streaming else { return }

        self.store = store
        conversation.wrappedValue.messages.append(
            Message(
                role: .user,
                content: trimmed,
                attachments: attachments.isEmpty ? nil : attachments,
                model: model
            )
        )
        state = .streaming

        task = Task { [weak self] in
            do {
                try await self?.runConversationLoop(
                    in: conversation,
                    provider: provider,
                    tools: tools,
                    memoryContext: memoryContext
                )
                self?.state = .idle
            } catch is CancellationError {
                self?.state = .idle
            } catch let error as OllamaClientError {
                self?.fail(error.errorDescription ?? "Erreur.", in: conversation)
            } catch let error as OpenAICompatibleError {
                self?.fail(error.errorDescription ?? "Erreur.", in: conversation)
            } catch let error as AnthropicClientError {
                self?.fail(error.errorDescription ?? "Erreur.", in: conversation)
            } catch let error as GoogleClientError {
                self?.fail(error.errorDescription ?? "Erreur.", in: conversation)
            } catch {
                self?.fail(error.localizedDescription, in: conversation)
            }
        }
    }

    /// Records a failed send as a persisted `.error` message in the
    /// conversation (shown inline, never sent to the LLM) and flags the
    /// state so the deprecated-model pruning hook can react. The empty
    /// streaming placeholder is already removed by the loop's `defer`.
    private func fail(_ message: String, in conversation: Binding<Conversation>) {
        conversation.wrappedValue.messages.append(
            Message(role: .error, content: message)
        )
        state = .failed(message: message)
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - Internals

    /// Resolves a message's image attachments to on-disk file URLs the
    /// multimodal provider can load. Empty when there's no store wired or
    /// the message has no attachments.
    private func resolveImageURLs(for message: Message, conversationID: UUID) -> [URL] {
        guard let store, let attachments = message.attachments, !attachments.isEmpty else { return [] }
        return attachments.map { store.attachmentURL(conversationID: conversationID, $0) }
    }

    /// Multi-round loop: ask the provider for a turn, append text deltas to
    /// the current assistant message and collect any tool calls. If tool
    /// calls came back, execute them, append the toolCall + toolResult
    /// messages to the conversation, and loop. Otherwise we're done.
    private func runConversationLoop(
        in conversation: Binding<Conversation>,
        provider: any LLMProvider,
        tools: ToolRegistry,
        memoryContext: String?
    ) async throws {
        // One-shot guard for the reasoning-only retry below.
        var reasoningOnlyRetryUsed = false
        for round in 0..<Self.maxToolRounds {
            if Task.isCancelled { return }

            // Fresh empty assistant message for this round's text output.
            let assistant = Message(role: .assistant, content: "")
            let assistantID = assistant.id
            conversation.wrappedValue.messages.append(assistant)

            // Drop the placeholder if nothing was emitted (text or reasoning)
            // by the time we leave this round — runs on success, cancellation
            // and thrown errors alike, so a failed round doesn't leave a "…"
            // bubble in the transcript. Tool calls (if any) carry their own
            // UI cards. Reasoning kept because the provider expects it back
            // in the next round's history.
            defer {
                if let idx = conversation.wrappedValue.messages.firstIndex(where: { $0.id == assistantID }),
                   conversation.wrappedValue.messages[idx].content.isEmpty,
                   (conversation.wrappedValue.messages[idx].reasoningContent ?? "").isEmpty,
                   (conversation.wrappedValue.messages[idx].attachments ?? []).isEmpty {
                    conversation.wrappedValue.messages.remove(at: idx)
                }
            }

            // Inject long-term memory as a leading system message (never
            // persisted to the conversation — purely request-time context).
            var history: [ChatMessage] = []
            if let memoryContext, !memoryContext.isEmpty {
                history.append(ChatMessage(role: .system, content: memoryContext))
            }
            let conversationID = conversation.wrappedValue.id
            history += conversation.wrappedValue.messages
                .dropLast()
                .compactMap { ChatMessage($0, imageURLs: self.resolveImageURLs(for: $0, conversationID: conversationID)) }

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
                case .imageOutput(let data, let mimeType):
                    // Persist a model-generated image as an attachment on the
                    // assistant message (needs the store wired via send()).
                    if let store,
                       let idx = conversation.wrappedValue.messages.firstIndex(where: { $0.id == assistantID }) {
                        let ext = mimeType.hasSuffix("png") ? "png"
                            : mimeType.hasSuffix("webp") ? "webp" : "jpg"
                        if let attachment = store.saveAttachment(
                            data, conversationID: conversation.wrappedValue.id, ext: ext) {
                            var atts = conversation.wrappedValue.messages[idx].attachments ?? []
                            atts.append(attachment)
                            conversation.wrappedValue.messages[idx].attachments = atts
                        }
                    }
                case .metrics(let metrics):
                    if let idx = conversation.wrappedValue.messages.firstIndex(where: { $0.id == assistantID }) {
                        conversation.wrappedValue.messages[idx].metrics = metrics
                    }
                case .toolCall(let id, let name, let argumentsJSON, let signature):
                    pendingCalls.append((id, name, argumentsJSON, signature))
                }
            }

            if pendingCalls.isEmpty {
                // Thinking models (e.g. LFM2.5 on MLX) sometimes finish
                // their reasoning and stop without ever emitting the
                // answer. Retry the round once — the dead-end bubble is
                // dropped, same prompt, fresh sample. If it happens again,
                // say so in the transcript instead of ending in silence.
                if let idx = conversation.wrappedValue.messages.firstIndex(where: { $0.id == assistantID }) {
                    let message = conversation.wrappedValue.messages[idx]
                    let hasText = !message.content
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let reasoningOnly = !hasText
                        && !(message.reasoningContent ?? "").isEmpty
                        && (message.attachments ?? []).isEmpty
                    if reasoningOnly {
                        if !reasoningOnlyRetryUsed {
                            reasoningOnlyRetryUsed = true
                            conversation.wrappedValue.messages.remove(at: idx)
                            continue
                        }
                        conversation.wrappedValue.messages[idx].content =
                            "Le modèle a terminé sa réflexion sans formuler de réponse — relance ta question."
                    }
                }
                return
            }

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
