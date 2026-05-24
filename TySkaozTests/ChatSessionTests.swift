import Foundation
import SwiftUI
import Testing
@testable import TySkaoz

@MainActor
@Suite(.serialized)
struct ChatSessionTests {

    @Test
    func appendsUserAndStreamsAssistantContent() async throws {
        let session = ChatSession()
        let provider = MockProvider(deltas: ["Sa", "lut"])

        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        session.send(text: "Bonjour", in: binding, using: provider)
        try await waitUntil { session.state == .idle }

        #expect(conversation.messages.count == 2)
        #expect(conversation.messages[0].role == .user)
        #expect(conversation.messages[0].content == "Bonjour")
        #expect(conversation.messages[1].role == .assistant)
        #expect(conversation.messages[1].content == "Salut")
    }

    @Test
    func ignoresEmptyDraft() {
        let session = ChatSession()
        let provider = MockProvider(deltas: [])

        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        session.send(text: "   ", in: binding, using: provider)

        #expect(conversation.messages.isEmpty)
        #expect(session.state == .idle)
    }

    @Test
    func surfacesFailure() async throws {
        let provider = ThrowingProvider(error: OllamaClientError.http(status: 500))
        let session = ChatSession()

        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        session.send(text: "Bonjour", in: binding, using: provider)
        try await waitUntil {
            if case .failed = session.state { return true }
            return false
        }

        if case .failed(let msg) = session.state {
            #expect(msg.contains("500"))
        } else {
            Issue.record("expected .failed state")
        }
        #expect(conversation.messages.first?.role == .user)
    }

    @Test
    func stopPreservesPartialResponse() async throws {
        let provider = HangingProvider(initialDelta: "partial")
        let session = ChatSession()

        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        session.send(text: "Bonjour", in: binding, using: provider)
        try await waitUntil { conversation.messages.last?.content == "partial" }

        session.stop()
        try await waitUntil { session.state == .idle }

        #expect(conversation.messages.last?.content == "partial")
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

private struct ThrowingProvider: LLMProvider {
    let id = "throw"
    let displayName = "Throwing"
    let error: Error

    func availability() async -> ProviderAvailability { .ready }

    func chat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

private struct HangingProvider: LLMProvider {
    let id = "hang"
    let displayName = "Hanging"
    let initialDelta: String

    func availability() async -> ProviderAvailability { .ready }

    func chat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(initialDelta)
            // Never finishes; the test stops the session instead.
        }
    }
}
