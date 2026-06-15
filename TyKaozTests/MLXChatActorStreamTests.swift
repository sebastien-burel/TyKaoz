import Foundation
import Testing
@testable import TyKaoz

/// Covers the streaming marker parser that strips reasoning / tool-call
/// envelopes out of the answer. The real symptom: Qwen 3 emits its
/// chain of thought inside `<think>…</think>` and, without routing, the
/// whole reasoning block leaked into the chat view as the answer.
@Suite
struct MLXChatActorStreamTests {

    /// Concatenates the text and reasoning streams separately.
    private func partition(_ events: [StreamEvent]) -> (text: String, reasoning: String) {
        var text = "", reasoning = ""
        for event in events {
            switch event {
            case .textDelta(let t): text += t
            case .reasoningDelta(let r): reasoning += r
            default: break
            }
        }
        return (text, reasoning)
    }

    @Test
    func thinkBlockRoutesToReasoningNotText() async {
        let events = await MLXChatActor.collectStreamEventsForTests(
            ["<think>Je réfléchis au problème.</think>Voici la réponse."],
            gemma: false
        )
        let (text, reasoning) = partition(events)
        #expect(reasoning.contains("Je réfléchis au problème."))
        #expect(text.contains("Voici la réponse."))
        #expect(!text.contains("Je réfléchis"))
        #expect(!text.contains("<think>"))
    }

    @Test
    func thinkMarkersSplitAcrossChunks() async {
        let events = await MLXChatActor.collectStreamEventsForTests(
            ["<th", "ink>pensée", " secrète</thi", "nk>réponse"],
            gemma: false
        )
        let (text, reasoning) = partition(events)
        #expect(reasoning.contains("pensée secrète"))
        #expect(text == "réponse")
    }

    @Test
    func plainTextPassesThrough() async {
        let events = await MLXChatActor.collectStreamEventsForTests(
            ["Bonjour ", "tout le monde."],
            gemma: false
        )
        let (text, reasoning) = partition(events)
        #expect(text == "Bonjour tout le monde.")
        #expect(reasoning.isEmpty)
    }

    /// Gemma 4 26B emits Hermes-style tool calls (`<tool_call>{json}
    /// </tool_call>`) rather than the native `call:…<tool_call|>` form;
    /// both must route to `.toolCall` without leaking raw text.
    @Test
    func gemmaHermesToolCallIsRouted() async {
        let events = await MLXChatActor.collectStreamEventsForTests(
            ["<tool_call>{\"name\":\"current_datetime\",\"arguments\":{}}</tool_call>"],
            gemma: true
        )
        let calls = events.compactMap { event -> String? in
            if case .toolCall(_, let name, _, _) = event { return name }
            return nil
        }
        #expect(calls == ["current_datetime"])
        let (text, _) = partition(events)
        #expect(!text.contains("tool_call"))
    }

    /// Regression: the Gemma 4 channel marker still routes to reasoning
    /// after the parser was generalised.
    @Test
    func gemmaChannelStillRoutesToReasoning() async {
        let events = await MLXChatActor.collectStreamEventsForTests(
            ["<|channel>analyse interne<channel|>Réponse finale."],
            gemma: true
        )
        let (text, reasoning) = partition(events)
        #expect(reasoning.contains("analyse interne"))
        #expect(text.contains("Réponse finale."))
    }
}
