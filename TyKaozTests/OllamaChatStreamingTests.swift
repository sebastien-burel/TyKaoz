import Foundation
import Testing
@testable import TyKaoz

@Suite(.serialized) @MainActor
struct OllamaChatStreamingTests {

    // MARK: - Chunk parsing

    @Test
    func parsesTextDelta() throws {
        let line = Data(#"{"model":"llama","message":{"role":"assistant","content":"Bonjour"},"done":false}"#.utf8)
        let info = try OllamaClient.parseChunk(line: line)
        #expect(info.textDelta == "Bonjour")
        #expect(info.toolCalls.isEmpty)
        #expect(info.done == false)
    }

    @Test
    func parsesToolCallChunk() throws {
        let line = Data(#"{"model":"llama","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"fetch_url","arguments":{"url":"https://example.com"}}}]},"done":false}"#.utf8)
        let info = try OllamaClient.parseChunk(line: line)
        #expect(info.textDelta == nil)
        #expect(info.toolCalls.count == 1)
        #expect(info.toolCalls[0].name == "fetch_url")
        // arguments round-tripped to JSON text
        let argsData = Data(info.toolCalls[0].argumentsJSON.utf8)
        let parsed = try JSONSerialization.jsonObject(with: argsData) as? [String: Any]
        #expect(parsed?["url"] as? String == "https://example.com")
        // ID is synthesised (Ollama doesn't ship one)
        #expect(!info.toolCalls[0].id.isEmpty)
    }

    @Test
    func doneFlagFlips() throws {
        let line = Data(#"{"model":"llama","message":{"role":"assistant","content":""},"done":true}"#.utf8)
        let info = try OllamaClient.parseChunk(line: line)
        #expect(info.done == true)
    }

    @Test
    func ignoresBlankLines() throws {
        let info = try OllamaClient.parseChunk(line: Data())
        #expect(info.textDelta == nil)
        #expect(info.toolCalls.isEmpty)
        #expect(info.done == false)
    }

    @Test
    func throwsOnMalformedJSON() {
        let line = Data("not json".utf8)
        #expect(throws: OllamaClientError.self) {
            _ = try OllamaClient.parseChunk(line: line)
        }
    }

    // MARK: - Body building

    @Test
    func bodyEmbedsToolDefinitions() throws {
        let tool = ToolSpec(
            name: "current_datetime",
            description: "Returns now.",
            inputSchemaJSON: #"{"type":"object","properties":{}}"#
        )
        let body = try OllamaClient.buildBody(
            model: "llama3.2",
            messages: [ChatMessage(role: .user, content: "Heure ?")],
            tools: [tool]
        )
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let tools = parsed?["tools"] as? [[String: Any]]
        #expect(tools?.count == 1)
        let function = tools?[0]["function"] as? [String: Any]
        #expect(function?["name"] as? String == "current_datetime")
        #expect(function?["parameters"] is [String: Any])
    }

    @Test
    func bodyMergesToolCallsIntoAssistantMessage() throws {
        let history: [ChatMessage] = [
            ChatMessage(role: .user, content: "Heure ?"),
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
        let body = try OllamaClient.buildBody(
            model: "llama3.2",
            messages: history,
            tools: []
        )
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = parsed?["messages"] as? [[String: Any]]
        #expect(messages?.count == 3)

        // 1st: user
        #expect(messages?[0]["role"] as? String == "user")

        // 2nd: synthesised assistant with tool_calls
        let assistant = messages?[1]
        #expect(assistant?["role"] as? String == "assistant")
        let calls = assistant?["tool_calls"] as? [[String: Any]]
        #expect(calls?.count == 1)
        let fn = calls?[0]["function"] as? [String: Any]
        #expect(fn?["name"] as? String == "current_datetime")
        // arguments must be a JSON OBJECT (Ollama-specific, unlike OpenAI's
        // stringified arguments).
        #expect(fn?["arguments"] is [String: Any])

        // 3rd: tool result with role="tool"
        let toolMsg = messages?[2]
        #expect(toolMsg?["role"] as? String == "tool")
        #expect(toolMsg?["content"] as? String == "2026-05-26T20:00:00Z")
    }
}
