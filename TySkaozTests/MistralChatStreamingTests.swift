import Foundation
import Testing
@testable import TySkaoz

@Suite(.serialized) @MainActor
struct MistralChatStreamingTests {

    @Test
    func parsesContentDelta() throws {
        let line = Data(#"data: {"choices":[{"delta":{"content":"Bonjour"},"finish_reason":null}]}"#.utf8)
        let result = try MistralClient.parseLine(line)
        #expect(result.delta == "Bonjour")
        #expect(result.done == false)
    }

    @Test
    func detectsFinishReasonAsDone() throws {
        let line = Data(#"data: {"choices":[{"delta":{"content":""},"finish_reason":"stop"}]}"#.utf8)
        let result = try MistralClient.parseLine(line)
        #expect(result.delta == nil)
        #expect(result.done == true)
    }

    @Test
    func detectsDONESentinel() throws {
        let line = Data("data: [DONE]".utf8)
        let result = try MistralClient.parseLine(line)
        #expect(result.delta == nil)
        #expect(result.done == true)
    }

    @Test
    func ignoresEventAndIDLines() throws {
        let event = Data("event: completion".utf8)
        let id = Data("id: chatcmpl-abc".utf8)
        let blank = Data()
        #expect(try MistralClient.parseLine(event).delta == nil)
        #expect(try MistralClient.parseLine(event).done == false)
        #expect(try MistralClient.parseLine(id).delta == nil)
        #expect(try MistralClient.parseLine(id).done == false)
        #expect(try MistralClient.parseLine(blank).delta == nil)
        #expect(try MistralClient.parseLine(blank).done == false)
    }

    @Test
    func throwsOnMalformedDataJSON() {
        let line = Data("data: not json".utf8)
        #expect(throws: MistralClientError.self) {
            _ = try MistralClient.parseLine(line)
        }
    }
}
