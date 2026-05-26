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
        let provider = MockProvider(events: [.textDelta("Sa"), .textDelta("lut")])

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
        let provider = MockProvider(events: [])

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

    // MARK: - Tool calling loop

    @Test
    func executesToolCallAndContinuesWithResult() async throws {
        // Round 1: provider asks for current_datetime, no text.
        // Round 2: provider replies with text using the result.
        let provider = ScriptedProvider(rounds: [
            [.toolCall(id: "call-1", name: "current_datetime", argumentsJSON: "{}")],
            [.textDelta("Il est ".self), .textDelta("midi.")]
        ])
        let session = ChatSession()
        let tools = ToolRegistry(tools: [CurrentDateTimeTool()])

        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        session.send(text: "Heure ?", in: binding, using: provider, tools: tools)
        try await waitUntil { session.state == .idle }

        // Expected sequence: user, toolCall, toolResult, assistant
        #expect(conversation.messages.count == 4)
        #expect(conversation.messages[0].role == .user)
        #expect(conversation.messages[1].role == .toolCall)
        #expect(conversation.messages[1].toolName == "current_datetime")
        #expect(conversation.messages[1].toolCallID == "call-1")
        #expect(conversation.messages[2].role == .toolResult)
        #expect(conversation.messages[2].toolCallID == "call-1")
        #expect(conversation.messages[2].toolIsError == false)
        #expect(conversation.messages[3].role == .assistant)
        #expect(conversation.messages[3].content == "Il est midi.")
    }

    @Test
    func errorFromToolSurfacedAsToolResultWithIsError() async throws {
        let provider = ScriptedProvider(rounds: [
            [.toolCall(id: "x", name: "unknown_tool", argumentsJSON: "{}")],
            [.textDelta("Oups.")]
        ])
        let session = ChatSession()
        let tools = ToolRegistry(tools: [CurrentDateTimeTool()])

        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        session.send(text: "Test", in: binding, using: provider, tools: tools)
        try await waitUntil { session.state == .idle }

        let resultMsg = conversation.messages.first { $0.role == .toolResult }
        #expect(resultMsg?.toolIsError == true)
        #expect(resultMsg?.content.contains("Unknown tool") == true)
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

    func chat(messages: [ChatMessage], tools: [ToolSpec]) -> AsyncThrowingStream<StreamEvent, Error> {
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

    func chat(messages: [ChatMessage], tools: [ToolSpec]) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(initialDelta))
            // Never finishes; the test stops the session instead.
        }
    }
}

/// Emits a pre-baked sequence of events per chat() invocation. Used to drive
/// the multi-round tool calling loop in tests.
private final class ScriptedProvider: LLMProvider, @unchecked Sendable {
    let id = "scripted"
    let displayName = "Scripted"

    private let rounds: [[StreamEvent]]
    private var nextRound = 0
    private let lock = NSLock()

    init(rounds: [[StreamEvent]]) {
        self.rounds = rounds
    }

    func availability() async -> ProviderAvailability { .ready }

    func chat(messages: [ChatMessage], tools: [ToolSpec]) -> AsyncThrowingStream<StreamEvent, Error> {
        let events = lock.withLock { () -> [StreamEvent] in
            guard nextRound < rounds.count else { return [] }
            let evts = rounds[nextRound]
            nextRound += 1
            return evts
        }
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
