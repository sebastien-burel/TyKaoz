import Foundation
import SwiftUI
import Testing
@testable import TySkaoz

@MainActor
@Suite(.serialized)
struct LLMProviderTests {

    @Test
    func mockProviderImplementsProtocolAndStreams() async throws {
        let mock = MockProvider(events: [.textDelta("Bon"), .textDelta("jour")])

        var collected: [String] = []
        for try await event in mock.chat(messages: [ChatMessage(role: .user, content: "Salut")], tools: []) {
            if case .textDelta(let text) = event {
                collected.append(text)
            }
        }
        #expect(collected == ["Bon", "jour"])
    }

    @Test
    func mockProviderReportsAvailability() async {
        let mock = MockProvider(events: [])
        #expect(await mock.availability() == .ready)

        let downed = MockProvider(events: [], availability: .unavailable(reason: "down"))
        #expect(await downed.availability() == .unavailable(reason: "down"))
    }

    @Test
    func chatSessionWorksWithAnyLLMProvider() async throws {
        let mock = MockProvider(events: [.textDelta("Sa"), .textDelta("lut")])
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

/// Minimal LLMProvider implementation that emits a pre-baked list of events
/// in order. Used to exercise the protocol surface and the ChatSession loop
/// without going through any HTTP code.
struct MockProvider: LLMProvider {
    let id = "mock"
    let displayName = "Mock"
    let events: [StreamEvent]
    let availabilityValue: ProviderAvailability

    init(events: [StreamEvent], availability: ProviderAvailability = .ready) {
        self.events = events
        self.availabilityValue = availability
    }

    func availability() async -> ProviderAvailability { availabilityValue }

    func chat(messages: [ChatMessage], tools: [ToolSpec]) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
