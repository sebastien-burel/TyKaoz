import Foundation
import Testing
@testable import TyKaoz

/// Covers the Gemma 4 tool-call payload parser. The streaming
/// interceptor relies on this; mis-parsing a payload leaks raw
/// text into the chat view (real symptom we saw with bge-m3 +
/// `search_wiki`).
@Suite
struct MLXChatActorGemma4Tests {

    @Test
    func parsesSimpleStringArg() throws {
        let raw = "call:search_wiki{query:<|\"|>sucre<|\"|>}"
        let parsed = try #require(MLXChatActor.parseGemma4PayloadForTests(raw))
        #expect(parsed.name == "search_wiki")
        let dict = try jsonDict(parsed.argumentsJSON)
        #expect(dict["query"] as? String == "sucre")
    }

    @Test
    func parsesMultipleStringArgs() throws {
        let raw = "call:write_wiki_page{path:<|\"|>sucre.md<|\"|>,content:<|\"|>Hello, world<|\"|>}"
        let parsed = try #require(MLXChatActor.parseGemma4PayloadForTests(raw))
        #expect(parsed.name == "write_wiki_page")
        let dict = try jsonDict(parsed.argumentsJSON)
        #expect(dict["path"] as? String == "sucre.md")
        // The comma in "Hello, world" must survive — splits on
        // comma outside escape markers only.
        #expect(dict["content"] as? String == "Hello, world")
    }

    @Test
    func parsesNumericArg() throws {
        let raw = "call:set_limit{count:42}"
        let parsed = try #require(MLXChatActor.parseGemma4PayloadForTests(raw))
        let dict = try jsonDict(parsed.argumentsJSON)
        #expect(dict["count"] as? Int == 42)
    }

    @Test
    func returnsNilOnMalformedPayload() {
        // No `call:` prefix → not a tool call.
        #expect(MLXChatActor.parseGemma4PayloadForTests("hello world") == nil)
        // Missing close brace.
        #expect(MLXChatActor.parseGemma4PayloadForTests("call:foo{key:value") == nil)
    }

    /// The model's second-format envelope: pseudo-JSON with
    /// malformed keys + escape-wrapped string values. Repro from
    /// a real chat session that triggered `brave_web_search`.
    @Test
    func parsesJSONStyleWithMalformedKey() throws {
        let raw = #"{"name":"brave_web_search","arguments":{"q:<|"|>composition chimique du sucre types et effets sur la santé<|"|>}}"#
        let parsed = try #require(MLXChatActor.parseGemma4PayloadForTests(raw))
        #expect(parsed.name == "brave_web_search")
        let dict = try jsonDict(parsed.argumentsJSON)
        #expect(dict["q"] as? String == "composition chimique du sucre types et effets sur la santé")
    }

    @Test
    func parsesJSONStyleWithMultipleEscapedArgs() throws {
        let raw = #"{"name":"write_wiki_page","arguments":{"path:<|"|>note.md<|"|>,"content:<|"|>Hello, world<|"|>}}"#
        let parsed = try #require(MLXChatActor.parseGemma4PayloadForTests(raw))
        #expect(parsed.name == "write_wiki_page")
        let dict = try jsonDict(parsed.argumentsJSON)
        #expect(dict["path"] as? String == "note.md")
        #expect(dict["content"] as? String == "Hello, world")
    }

    // MARK: - Helpers

    private func jsonDict(_ json: String) throws -> [String: Any] {
        let data = try #require(json.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data)
        return try #require(parsed as? [String: Any])
    }
}
