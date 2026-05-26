import Foundation
import Testing
@testable import TySkaoz

@Suite(.serialized) @MainActor
struct AnthropicStreamingTests {

    @Test
    func parsesTextDeltaEvent() throws {
        let line = Data(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Bonjour"}}"#.utf8)
        let info = try AnthropicClient.parseLine(line)
        #expect(info.event?.type == "content_block_delta")
        #expect(info.event?.delta?.type == "text_delta")
        #expect(info.event?.delta?.text == "Bonjour")
    }

    @Test
    func parsesContentBlockStartForToolUse() throws {
        let line = Data(#"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_abc","name":"fetch_url"}}"#.utf8)
        let info = try AnthropicClient.parseLine(line)
        #expect(info.event?.type == "content_block_start")
        #expect(info.event?.index == 1)
        #expect(info.event?.contentBlock?.type == "tool_use")
        #expect(info.event?.contentBlock?.id == "toolu_abc")
        #expect(info.event?.contentBlock?.name == "fetch_url")
    }

    @Test
    func parsesInputJSONDelta() throws {
        let line = Data(#"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"url"}}"#.utf8)
        let info = try AnthropicClient.parseLine(line)
        #expect(info.event?.delta?.type == "input_json_delta")
        #expect(info.event?.delta?.partialJSON == "{\"url")
    }

    @Test
    func parsesContentBlockStop() throws {
        let line = Data(#"data: {"type":"content_block_stop","index":0}"#.utf8)
        let info = try AnthropicClient.parseLine(line)
        #expect(info.event?.type == "content_block_stop")
        #expect(info.event?.index == 0)
    }

    @Test
    func parsesMessageStop() throws {
        let line = Data(#"data: {"type":"message_stop"}"#.utf8)
        let info = try AnthropicClient.parseLine(line)
        #expect(info.event?.type == "message_stop")
    }

    @Test
    func ignoresMetadataEvents() throws {
        let starts = [
            Data(#"data: {"type":"message_start","message":{"id":"msg_x"}}"#.utf8),
            Data(#"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#.utf8),
            Data(#"data: {"type":"ping"}"#.utf8)
        ]
        for line in starts {
            let info = try AnthropicClient.parseLine(line)
            #expect(info.event != nil)
        }
    }

    @Test
    func ignoresEventLines() throws {
        let info = try AnthropicClient.parseLine(Data("event: content_block_delta".utf8))
        #expect(info.event == nil)
    }

    @Test
    func throwsOnMalformedDataJSON() {
        let line = Data("data: not json".utf8)
        #expect(throws: AnthropicClientError.self) {
            _ = try AnthropicClient.parseLine(line)
        }
    }

    // MARK: - Body building

    @Test
    func bodyEmbedsToolsAsInputSchemaObjects() throws {
        let tool = ToolSpec(
            name: "fetch_url",
            description: "Fetch a URL.",
            inputSchemaJSON: #"{"type":"object","properties":{"url":{"type":"string"}},"required":["url"]}"#
        )
        let body = try AnthropicClient.buildBody(
            model: "claude",
            messages: [ChatMessage(role: .user, content: "Salut")],
            tools: [tool],
            maxTokens: 1024
        )
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let tools = parsed?["tools"] as? [[String: Any]]
        #expect(tools?.count == 1)
        #expect(tools?[0]["name"] as? String == "fetch_url")
        // input_schema must be a JSON object, not a string.
        #expect(tools?[0]["input_schema"] is [String: Any])
    }

    @Test
    func bodyMergesToolCallsIntoAssistantContentBlocks() throws {
        let history: [ChatMessage] = [
            ChatMessage(role: .user, content: "Heure ?"),
            ChatMessage(
                role: .toolCall,
                content: "{}",
                toolCallID: "toolu_1",
                toolName: "current_datetime"
            ),
            ChatMessage(
                role: .toolResult,
                content: "2026-05-26T20:00:00Z",
                toolCallID: "toolu_1",
                toolIsError: false
            )
        ]
        let body = try AnthropicClient.buildBody(
            model: "claude",
            messages: history,
            tools: [],
            maxTokens: 1024
        )
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = parsed?["messages"] as? [[String: Any]]
        #expect(messages?.count == 3)

        // 1st: user with text block
        let userMsg = messages?[0]
        #expect(userMsg?["role"] as? String == "user")
        let userBlocks = userMsg?["content"] as? [[String: Any]]
        #expect(userBlocks?.first?["type"] as? String == "text")

        // 2nd: synthesized assistant with tool_use block
        let assistant = messages?[1]
        #expect(assistant?["role"] as? String == "assistant")
        let aBlocks = assistant?["content"] as? [[String: Any]]
        #expect(aBlocks?.first?["type"] as? String == "tool_use")
        #expect(aBlocks?.first?["id"] as? String == "toolu_1")
        #expect(aBlocks?.first?["name"] as? String == "current_datetime")

        // 3rd: user with tool_result block (Anthropic puts tool results in user)
        let toolUser = messages?[2]
        #expect(toolUser?["role"] as? String == "user")
        let tBlocks = toolUser?["content"] as? [[String: Any]]
        #expect(tBlocks?.first?["type"] as? String == "tool_result")
        #expect(tBlocks?.first?["tool_use_id"] as? String == "toolu_1")
    }

    @Test
    func bodyExtractsSystemFromMessages() throws {
        let history: [ChatMessage] = [
            ChatMessage(role: .system, content: "Tu es utile."),
            ChatMessage(role: .user, content: "Salut")
        ]
        let body = try AnthropicClient.buildBody(
            model: "claude",
            messages: history,
            tools: [],
            maxTokens: 1024
        )
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(parsed?["system"] as? String == "Tu es utile.")
        // System messages are NOT in messages array.
        let messages = parsed?["messages"] as? [[String: Any]]
        #expect(messages?.count == 1)
        #expect(messages?[0]["role"] as? String == "user")
    }
}
