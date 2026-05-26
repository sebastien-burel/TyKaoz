import Foundation
import Testing
@testable import TySkaoz

@Suite(.serialized) @MainActor
struct GoogleStreamingTests {

    // MARK: - Text parsing

    @Test
    func extractsTextFromCandidate() throws {
        let line = Data(#"data: {"candidates":[{"content":{"parts":[{"text":"Bonjour"}],"role":"model"}}]}"#.utf8)
        let info = try GoogleClient.parseLine(line)
        #expect(info.textDelta == "Bonjour")
        #expect(info.toolCalls.isEmpty)
        #expect(info.done == false)
    }

    @Test
    func joinsMultiplePartsInOneChunk() throws {
        let line = Data(#"data: {"candidates":[{"content":{"parts":[{"text":"Sa"},{"text":"lut"}]}}]}"#.utf8)
        let info = try GoogleClient.parseLine(line)
        #expect(info.textDelta == "Salut")
    }

    @Test
    func finishReasonMarksDone() throws {
        let line = Data(#"data: {"candidates":[{"content":{"parts":[{"text":"."}]},"finishReason":"STOP"}]}"#.utf8)
        let info = try GoogleClient.parseLine(line)
        #expect(info.textDelta == ".")
        #expect(info.done == true)
    }

    @Test
    func emptyCandidateIsNoOp() throws {
        let line = Data(#"data: {"candidates":[]}"#.utf8)
        let info = try GoogleClient.parseLine(line)
        #expect(info.textDelta == nil)
        #expect(info.toolCalls.isEmpty)
    }

    @Test
    func ignoresBlankAndPreambles() throws {
        #expect(try GoogleClient.parseLine(Data()).textDelta == nil)
        #expect(try GoogleClient.parseLine(Data("event: anything".utf8)).textDelta == nil)
    }

    @Test
    func throwsOnMalformedDataJSON() {
        let line = Data("data: not json".utf8)
        #expect(throws: GoogleClientError.self) {
            _ = try GoogleClient.parseLine(line)
        }
    }

    // MARK: - Tool calls

    @Test
    func parsesFunctionCallPart() throws {
        let line = Data(#"data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"fetch_url","args":{"url":"https://example.com"}}}],"role":"model"}}]}"#.utf8)
        let info = try GoogleClient.parseLine(line)
        #expect(info.toolCalls.count == 1)
        let tc = info.toolCalls[0]
        #expect(tc.name == "fetch_url")
        // args round-tripped to JSON text:
        let decoded = try JSONSerialization.jsonObject(with: Data(tc.argumentsJSON.utf8)) as? [String: Any]
        #expect(decoded?["url"] as? String == "https://example.com")
        #expect(!tc.id.isEmpty) // synthesized if missing
    }

    @Test
    func mixedTextAndFunctionCallInSameChunk() throws {
        let line = Data(#"data: {"candidates":[{"content":{"parts":[{"text":"Je cherche…"},{"functionCall":{"name":"fetch_url","args":{}}}]}}]}"#.utf8)
        let info = try GoogleClient.parseLine(line)
        #expect(info.textDelta == "Je cherche…")
        #expect(info.toolCalls.count == 1)
    }

    // MARK: - Body building

    @Test
    func bodyWrapsToolsInFunctionDeclarations() throws {
        let tool = ToolSpec(
            name: "fetch_url",
            description: "Fetch a URL.",
            inputSchemaJSON: #"{"type":"object","properties":{"url":{"type":"string"}}}"#
        )
        let body = try GoogleClient.buildBody(
            model: "gemini",
            messages: [ChatMessage(role: .user, content: "Salut")],
            tools: [tool]
        )
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let toolsArray = parsed?["tools"] as? [[String: Any]]
        #expect(toolsArray?.count == 1)
        let decls = toolsArray?[0]["functionDeclarations"] as? [[String: Any]]
        #expect(decls?.count == 1)
        #expect(decls?[0]["name"] as? String == "fetch_url")
        #expect(decls?[0]["parameters"] is [String: Any])
    }

    @Test
    func contentsMergeAssistantTextAndToolCalls() throws {
        let history: [ChatMessage] = [
            ChatMessage(role: .user, content: "Heure ?"),
            ChatMessage(role: .assistant, content: "Je regarde."),
            ChatMessage(
                role: .toolCall,
                content: #"{"x":1}"#,
                toolCallID: "id-1",
                toolName: "current_datetime"
            ),
            ChatMessage(
                role: .toolResult,
                content: "2026-05-26T20:00:00Z",
                toolCallID: "id-1",
                toolIsError: false
            )
        ]
        let body = try GoogleClient.buildBody(
            model: "gemini",
            messages: history,
            tools: []
        )
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let contents = parsed?["contents"] as? [[String: Any]]
        #expect(contents?.count == 3)

        // user (text)
        #expect(contents?[0]["role"] as? String == "user")

        // model (text + functionCall)
        let modelParts = contents?[1]["parts"] as? [[String: Any]]
        #expect(contents?[1]["role"] as? String == "model")
        #expect(modelParts?.count == 2)
        #expect(modelParts?[0]["text"] as? String == "Je regarde.")
        let fc = modelParts?[1]["functionCall"] as? [String: Any]
        #expect(fc?["name"] as? String == "current_datetime")
        #expect(fc?["args"] is [String: Any])

        // user (functionResponse) — Gemini puts tool results in user role
        let toolParts = contents?[2]["parts"] as? [[String: Any]]
        #expect(contents?[2]["role"] as? String == "user")
        let fr = toolParts?[0]["functionResponse"] as? [String: Any]
        #expect(fr?["name"] as? String == "current_datetime")
        let resp = fr?["response"] as? [String: Any]
        #expect(resp?["content"] as? String == "2026-05-26T20:00:00Z")
    }

    @Test
    func systemMessagesGoToTopLevelSystemInstruction() throws {
        let history: [ChatMessage] = [
            ChatMessage(role: .system, content: "Be brief."),
            ChatMessage(role: .user, content: "Hi")
        ]
        let body = try GoogleClient.buildBody(model: "gemini", messages: history, tools: [])
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let si = parsed?["systemInstruction"] as? [String: Any]
        let parts = si?["parts"] as? [[String: Any]]
        #expect(parts?.first?["text"] as? String == "Be brief.")
        // System should NOT appear in contents
        let contents = parsed?["contents"] as? [[String: Any]]
        #expect(contents?.count == 1)
        #expect(contents?.first?["role"] as? String == "user")
    }
}
