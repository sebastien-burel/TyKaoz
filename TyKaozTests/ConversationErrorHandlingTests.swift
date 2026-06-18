import Foundation
import SwiftUI
import Testing
@testable import TyKaoz

/// Covers the per-conversation inline error handling: `.error` messages
/// render as their own banner (not folded into the intermediate-steps
/// disclosure) and are never forwarded to the LLM.
@MainActor
@Suite(.serialized)
struct ConversationErrorHandlingTests {

    @Test
    func turnLiftsErrorOutOfIntermediates() {
        let convo = Conversation(title: "t", messages: [
            Message(role: .user, content: "go"),
            Message(role: .toolCall, content: "{}", toolName: "x"),
            Message(role: .toolResult, content: "ok"),
            Message(role: .error, content: "Réponse HTTP 500."),
        ])
        let turns = convo.turns
        #expect(turns.count == 1)
        let turn = turns[0]
        #expect(turn.error?.content == "Réponse HTTP 500.")
        #expect(turn.finalAssistant == nil)
        // The error is pulled out — only the tool messages remain folded.
        #expect(turn.intermediates.count == 2)
        #expect(!turn.intermediates.contains { $0.role == .error })
    }

    @Test
    func turnKeepsFinalAssistantAlongsideError() {
        let convo = Conversation(title: "t", messages: [
            Message(role: .user, content: "go"),
            Message(role: .assistant, content: "voici"),
            Message(role: .error, content: "boom"),
        ])
        let turn = convo.turns[0]
        #expect(turn.finalAssistant?.content == "voici")
        #expect(turn.error?.content == "boom")
    }

    @Test
    func chatMessageMappingExcludesErrorRole() {
        // `.error` never maps to a provider message…
        #expect(ChatMessage(Message(role: .error, content: "x")) == nil)
        // …but the LLM-facing roles still do.
        #expect(ChatMessage(Message(role: .user, content: "hi"))?.role == .user)
        #expect(ChatMessage(Message(role: .assistant, content: "yo"))?.role == .assistant)
    }

    @Test
    func failedSendAppendsInlineErrorAndDropsPlaceholder() async throws {
        let session = ChatSession()
        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        session.send(text: "Bonjour", in: binding, using: FailingProvider())
        try await waitUntil { if case .failed = session.state { return true } else { return false } }

        // user message + the inline error; the empty assistant placeholder
        // is removed by the loop's defer.
        #expect(conversation.messages.map(\.role) == [.user, .error])
        #expect(conversation.messages.last?.content.isEmpty == false)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("waitUntil timed out")
    }
}

/// Streams nothing and throws — exercises ChatSession's failure path.
private struct FailingProvider: LLMProvider {
    let id = "failing"
    let displayName = "Failing"
    func availability() async -> ProviderAvailability { .ready }
    func chat(messages: [ChatMessage], tools: [ToolSpec]) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: Failure.boom)
        }
    }
    enum Failure: Error { case boom }
}
