import Foundation
import Testing
@testable import TyKaoz

@Suite(.serialized) @MainActor
struct OpenAICompatibleStreamingTests {

    // MARK: - Text deltas

    @Test
    func parsesContentDelta() throws {
        let line = Data(#"data: {"choices":[{"delta":{"content":"Bonjour"},"finish_reason":null}]}"#.utf8)
        let result = try OpenAICompatibleClient.parseLine(line)
        #expect(result.textDelta == "Bonjour")
        #expect(result.toolCallDeltas.isEmpty)
        #expect(result.done == false)
    }

    @Test
    func detectsFinishReasonAsDone() throws {
        let line = Data(#"data: {"choices":[{"delta":{"content":""},"finish_reason":"stop"}]}"#.utf8)
        let result = try OpenAICompatibleClient.parseLine(line)
        #expect(result.textDelta == nil)
        #expect(result.done == true)
    }

    @Test
    func detectsDONESentinel() throws {
        let line = Data("data: [DONE]".utf8)
        let result = try OpenAICompatibleClient.parseLine(line)
        #expect(result.textDelta == nil)
        #expect(result.done == true)
    }

    @Test
    func ignoresEventAndIDLines() throws {
        let event = Data("event: completion".utf8)
        let id = Data("id: chatcmpl-abc".utf8)
        let blank = Data()
        #expect(try OpenAICompatibleClient.parseLine(event).textDelta == nil)
        #expect(try OpenAICompatibleClient.parseLine(event).done == false)
        #expect(try OpenAICompatibleClient.parseLine(id).textDelta == nil)
        #expect(try OpenAICompatibleClient.parseLine(id).done == false)
        #expect(try OpenAICompatibleClient.parseLine(blank).textDelta == nil)
        #expect(try OpenAICompatibleClient.parseLine(blank).done == false)
    }

    @Test
    func throwsOnMalformedDataJSON() {
        let line = Data("data: not json".utf8)
        #expect(throws: OpenAICompatibleError.self) {
            _ = try OpenAICompatibleClient.parseLine(line)
        }
    }

    // MARK: - Tool call deltas

    @Test
    func parsesToolCallOpeningChunk() throws {
        let line = Data(#"data: {"choices":[{"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"fetch_url","arguments":""}}]}}]}"#.utf8)
        let info = try OpenAICompatibleClient.parseLine(line)
        #expect(info.textDelta == nil)
        #expect(info.toolCallDeltas.count == 1)
        let tc = info.toolCallDeltas[0]
        #expect(tc.index == 0)
        #expect(tc.id == "call_abc")
        #expect(tc.name == "fetch_url")
        #expect(tc.argumentsDelta == "")
    }

    @Test
    func parsesToolCallArgumentsContinuation() throws {
        let line = Data(#"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"url"}}]}}]}"#.utf8)
        let info = try OpenAICompatibleClient.parseLine(line)
        #expect(info.toolCallDeltas.count == 1)
        #expect(info.toolCallDeltas[0].id == nil)
        #expect(info.toolCallDeltas[0].name == nil)
        #expect(info.toolCallDeltas[0].argumentsDelta == "{\"url")
    }

    @Test
    func toolCallsFinishReasonMarksDone() throws {
        let line = Data(#"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#.utf8)
        let info = try OpenAICompatibleClient.parseLine(line)
        #expect(info.done == true)
        #expect(info.toolCallDeltas.isEmpty)
    }

    // MARK: - Body building

    @Test
    func bodyEmbedsToolDefinitionsAsObjects() throws {
        let tool = ToolSpec(
            name: "current_datetime",
            description: "Returns now in ISO 8601.",
            inputSchemaJSON: #"{"type":"object","properties":{},"additionalProperties":false}"#
        )
        let body = try OpenAICompatibleClient.buildBody(
            model: "test",
            messages: [ChatMessage(role: .user, content: "Heure ?")],
            tools: [tool]
        )
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let tools = parsed?["tools"] as? [[String: Any]]
        #expect(tools?.count == 1)
        let function = (tools?[0]["function"] as? [String: Any])
        #expect(function?["name"] as? String == "current_datetime")
        // The schema must be a JSON OBJECT (dictionary), not a string —
        // otherwise OpenAI rejects the request.
        #expect(function?["parameters"] is [String: Any])
    }

    @Test
    func bodyMergesToolCallsIntoAssistantMessage() throws {
        let history: [ChatMessage] = [
            ChatMessage(role: .user, content: "Quelle heure ?"),
            ChatMessage(
                role: .toolCall,
                content: "{}",
                toolCallID: "call_1",
                toolName: "current_datetime"
            ),
            ChatMessage(
                role: .toolResult,
                content: "2026-05-26T20:00:00Z",
                toolCallID: "call_1",
                toolIsError: false
            )
        ]
        let body = try OpenAICompatibleClient.buildBody(
            model: "test",
            messages: history,
            tools: []
        )
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = parsed?["messages"] as? [[String: Any]]
        #expect(messages?.count == 3)
        #expect(messages?[0]["role"] as? String == "user")

        // 2nd entry: synthetic assistant with tool_calls
        let assistant = messages?[1]
        #expect(assistant?["role"] as? String == "assistant")
        let calls = assistant?["tool_calls"] as? [[String: Any]]
        #expect(calls?.count == 1)
        #expect(calls?[0]["id"] as? String == "call_1")

        // 3rd entry: tool result with role="tool"
        let toolMsg = messages?[2]
        #expect(toolMsg?["role"] as? String == "tool")
        #expect(toolMsg?["tool_call_id"] as? String == "call_1")
        #expect(toolMsg?["content"] as? String == "2026-05-26T20:00:00Z")
    }
}
