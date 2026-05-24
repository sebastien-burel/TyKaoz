import Foundation
import SwiftUI
import Testing
@testable import TySkaoz

@MainActor
@Suite(.serialized)
struct ChatSessionTests {
    private let baseURL = URL(string: "http://localhost:11434")!

    @Test
    func appendsUserAndStreamsAssistantContent() async throws {
        let session = ChatSession { _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield("Sa")
                continuation.yield("lut")
                continuation.finish()
            }
        }

        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        session.send(text: "Bonjour", in: binding, model: "x", baseURL: baseURL)
        try await waitUntil { session.state == .idle }

        #expect(conversation.messages.count == 2)
        #expect(conversation.messages[0].role == .user)
        #expect(conversation.messages[0].content == "Bonjour")
        #expect(conversation.messages[1].role == .assistant)
        #expect(conversation.messages[1].content == "Salut")
    }

    @Test
    func ignoresEmptyDraft() {
        let session = ChatSession { _, _, _ in AsyncThrowingStream { $0.finish() } }
        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        session.send(text: "   ", in: binding, model: "x", baseURL: baseURL)

        #expect(conversation.messages.isEmpty)
        #expect(session.state == .idle)
    }

    @Test
    func surfacesFailure() async throws {
        let session = ChatSession { _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: OllamaClientError.http(status: 500))
            }
        }
        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        session.send(text: "Bonjour", in: binding, model: "x", baseURL: baseURL)
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
        // Stream that yields one delta then waits forever.
        let session = ChatSession { _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield("partial")
                // Never finish; the test stops the session instead.
            }
        }

        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        session.send(text: "Bonjour", in: binding, model: "x", baseURL: baseURL)

        // Give the streaming task a moment to consume the first delta.
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
