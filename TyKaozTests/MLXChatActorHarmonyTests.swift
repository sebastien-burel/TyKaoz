import Foundation
import Testing
@testable import TyKaoz

/// Covers the Harmony (gpt-oss) streaming parser. gpt-oss emits
/// channel-tagged messages (`<|channel|>…<|message|>…<|call|>`) that
/// mlx-swift-lm doesn't parse, so without this routing the raw tokens
/// leak into the chat and tool calls go undetected.
@Suite
struct MLXChatActorHarmonyTests {

    @Test
    func routesToolCallAndHidesAnalysis() async throws {
        // Real gpt-oss-20b repro: an analysis preamble followed by a
        // `commentary` tool call addressed to `functions.save_memory`.
        let raw = """
        <|channel|>analysis<|message|> We should call the function.<|end|>\
        <|start|>assistant<|channel|>commentary to=functions.save_memory \
        <|constrain|>json<|message|>\
        {"title":"User_Info","content":"Sébastien, né le 20 juillet 1967."}<|call|>
        """
        let events = await MLXChatActor.collectHarmonyEventsForTests([raw])

        // No raw Harmony tokens leak as answer text.
        #expect(plainText(events).isEmpty)

        let calls = toolCalls(events)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "save_memory")
        let dict = try jsonDict(try #require(calls.first?.json))
        #expect(dict["title"] as? String == "User_Info")
        #expect(dict["content"] as? String == "Sébastien, né le 20 juillet 1967.")

        // The analysis channel is routed to reasoning, never to text.
        #expect(reasoning(events).contains("We should call the function."))
    }

    @Test
    func streamsFinalChannelAsText() async {
        let raw = "<|channel|>final<|message|>Bonjour Sébastien !<|return|>"
        let events = await MLXChatActor.collectHarmonyEventsForTests([raw])
        #expect(plainText(events) == "Bonjour Sébastien !")
        #expect(toolCalls(events).isEmpty)
    }

    @Test
    func hidesAnalysisBeforeFinal() async {
        let raw = """
        <|channel|>analysis<|message|>Let me think.<|end|>\
        <|start|>assistant<|channel|>final<|message|>La réponse est 42.<|return|>
        """
        let events = await MLXChatActor.collectHarmonyEventsForTests([raw])
        #expect(plainText(events) == "La réponse est 42.")
        #expect(reasoning(events).contains("Let me think."))
    }

    @Test
    func survivesTokensSplitAcrossChunks() async throws {
        // Same tool call, but sliced so special tokens straddle chunk
        // boundaries — the streaming buffer must stitch them back.
        let full = """
        <|channel|>commentary to=functions.save_memory <|constrain|>json\
        <|message|>{"q":"sucre"}<|call|>
        """
        var chunks: [String] = []
        var idx = full.startIndex
        // 5-char slices to force splits inside `<|channel|>`, `<|message|>`, etc.
        while idx < full.endIndex {
            let end = full.index(idx, offsetBy: 5, limitedBy: full.endIndex) ?? full.endIndex
            chunks.append(String(full[idx..<end]))
            idx = end
        }
        let events = await MLXChatActor.collectHarmonyEventsForTests(chunks)
        #expect(plainText(events).isEmpty)
        let calls = toolCalls(events)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "save_memory")
        let dict = try jsonDict(try #require(calls.first?.json))
        #expect(dict["q"] as? String == "sucre")
    }

    // MARK: - Helpers

    private func plainText(_ events: [StreamEvent]) -> String {
        events.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }
            .joined()
    }

    private func reasoning(_ events: [StreamEvent]) -> String {
        events.compactMap { if case .reasoningDelta(let t) = $0 { return t } else { return nil } }
            .joined()
    }

    private func toolCalls(_ events: [StreamEvent]) -> [(name: String, json: String)] {
        events.compactMap {
            if case .toolCall(_, let name, let json, _) = $0 { return (name, json) }
            return nil
        }
    }

    private func jsonDict(_ json: String) throws -> [String: Any] {
        let data = try #require(json.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
