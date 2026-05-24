import Foundation
import SwiftUI
import Testing
@testable import TySkaoz

@MainActor
@Suite(.serialized)
struct LLMProviderTests {

    @Test
    func mockProviderImplementsProtocolAndStreams() async throws {
        let mock = MockProvider(deltas: ["Bon", "jour"])

        var collected: [String] = []
        for try await delta in mock.chat(messages: [
            ChatMessage(role: .user, content: "Salut")
        ]) {
            collected.append(delta)
        }
        #expect(collected == ["Bon", "jour"])
    }

    @Test
    func mockProviderReportsAvailability() async {
        let mock = MockProvider(deltas: [])
        #expect(await mock.availability() == .ready)

        let downed = MockProvider(deltas: [], availability: .unavailable(reason: "down"))
        #expect(await downed.availability() == .unavailable(reason: "down"))
    }

    @Test
    func chatSessionWorksWithAnyLLMProvider() async throws {
        let mock = MockProvider(deltas: ["Sa", "lut"])
        let chatSession = ChatSession()
        var conversation = Conversation(title: "test")
        let binding = Binding(get: { conversation }, set: { conversation = $0 })

        chatSession.send(text: "Bonjour", in: binding, using: mock)
        try await waitUntil { chatSession.state == .idle }

        #expect(conversation.messages.count == 2)
        #expect(conversation.messages[0].content == "Bonjour")
        #expect(conversation.messages[1].content == "Salut")
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

/// Minimal LLMProvider implementation used to confirm the protocol shape.
struct MockProvider: LLMProvider {
    let id = "mock"
    let displayName = "Mock"
    let deltas: [String]
    let availabilityValue: ProviderAvailability

    init(deltas: [String], availability: ProviderAvailability = .ready) {
        self.deltas = deltas
        self.availabilityValue = availability
    }

    func availability() async -> ProviderAvailability { availabilityValue }

    func chat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for delta in deltas {
                continuation.yield(delta)
            }
            continuation.finish()
        }
    }
}
