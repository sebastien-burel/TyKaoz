import Foundation
import Testing
@testable import TySkaoz

@Suite(.serialized) @MainActor
struct AnthropicStreamingTests {

    @Test
    func extractsTextDelta() throws {
        let line = Data(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Bonjour"}}"#.utf8)
        let result = try AnthropicClient.parseLine(line)
        #expect(result.delta == "Bonjour")
        #expect(result.done == false)
    }

    @Test
    func ignoresNonTextDelta() throws {
        let line = Data(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{}"}}"#.utf8)
        let result = try AnthropicClient.parseLine(line)
        #expect(result.delta == nil)
        #expect(result.done == false)
    }

    @Test
    func messageStopMarksDone() throws {
        let line = Data(#"data: {"type":"message_stop"}"#.utf8)
        let result = try AnthropicClient.parseLine(line)
        #expect(result.delta == nil)
        #expect(result.done == true)
    }

    @Test
    func ignoresMetadataEvents() throws {
        let starts = [
            Data(#"data: {"type":"message_start","message":{"id":"msg_x"}}"#.utf8),
            Data(#"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#.utf8),
            Data(#"data: {"type":"content_block_stop","index":0}"#.utf8),
            Data(#"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#.utf8),
            Data(#"data: {"type":"ping"}"#.utf8)
        ]
        for line in starts {
            let result = try AnthropicClient.parseLine(line)
            #expect(result.delta == nil)
            #expect(result.done == false)
        }
    }

    @Test
    func ignoresEventLines() throws {
        #expect(try AnthropicClient.parseLine(Data("event: content_block_delta".utf8)).delta == nil)
        #expect(try AnthropicClient.parseLine(Data("event: content_block_delta".utf8)).done == false)
    }

    @Test
    func throwsOnMalformedDataJSON() {
        let line = Data("data: not json".utf8)
        #expect(throws: AnthropicClientError.self) {
            _ = try AnthropicClient.parseLine(line)
        }
    }
}
