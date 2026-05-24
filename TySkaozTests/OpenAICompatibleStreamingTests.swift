import Foundation
import Testing
@testable import TySkaoz

@Suite(.serialized) @MainActor
struct OpenAICompatibleStreamingTests {

    @Test
    func parsesContentDelta() throws {
        let line = Data(#"data: {"choices":[{"delta":{"content":"Bonjour"},"finish_reason":null}]}"#.utf8)
        let result = try OpenAICompatibleClient.parseLine(line)
        #expect(result.delta == "Bonjour")
        #expect(result.done == false)
    }

    @Test
    func detectsFinishReasonAsDone() throws {
        let line = Data(#"data: {"choices":[{"delta":{"content":""},"finish_reason":"stop"}]}"#.utf8)
        let result = try OpenAICompatibleClient.parseLine(line)
        #expect(result.delta == nil)
        #expect(result.done == true)
    }

    @Test
    func detectsDONESentinel() throws {
        let line = Data("data: [DONE]".utf8)
        let result = try OpenAICompatibleClient.parseLine(line)
        #expect(result.delta == nil)
        #expect(result.done == true)
    }

    @Test
    func ignoresEventAndIDLines() throws {
        let event = Data("event: completion".utf8)
        let id = Data("id: chatcmpl-abc".utf8)
        let blank = Data()
        #expect(try OpenAICompatibleClient.parseLine(event).delta == nil)
        #expect(try OpenAICompatibleClient.parseLine(event).done == false)
        #expect(try OpenAICompatibleClient.parseLine(id).delta == nil)
        #expect(try OpenAICompatibleClient.parseLine(id).done == false)
        #expect(try OpenAICompatibleClient.parseLine(blank).delta == nil)
        #expect(try OpenAICompatibleClient.parseLine(blank).done == false)
    }

    @Test
    func throwsOnMalformedDataJSON() {
        let line = Data("data: not json".utf8)
        #expect(throws: OpenAICompatibleError.self) {
            _ = try OpenAICompatibleClient.parseLine(line)
        }
    }
}
