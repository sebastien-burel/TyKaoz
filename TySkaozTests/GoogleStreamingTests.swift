import Foundation
import Testing
@testable import TySkaoz

@Suite(.serialized) @MainActor
struct GoogleStreamingTests {

    @Test
    func extractsTextFromCandidate() throws {
        let line = Data(#"data: {"candidates":[{"content":{"parts":[{"text":"Bonjour"}],"role":"model"}}]}"#.utf8)
        let result = try GoogleClient.parseLine(line)
        #expect(result.delta == "Bonjour")
        #expect(result.done == false)
    }

    @Test
    func joinsMultiplePartsInOneChunk() throws {
        let line = Data(#"data: {"candidates":[{"content":{"parts":[{"text":"Sa"},{"text":"lut"}]}}]}"#.utf8)
        let result = try GoogleClient.parseLine(line)
        #expect(result.delta == "Salut")
        #expect(result.done == false)
    }

    @Test
    func finishReasonMarksDone() throws {
        let line = Data(#"data: {"candidates":[{"content":{"parts":[{"text":"."}]},"finishReason":"STOP"}]}"#.utf8)
        let result = try GoogleClient.parseLine(line)
        #expect(result.delta == ".")
        #expect(result.done == true)
    }

    @Test
    func emptyCandidateIsNoOp() throws {
        let line = Data(#"data: {"candidates":[]}"#.utf8)
        let result = try GoogleClient.parseLine(line)
        #expect(result.delta == nil)
        #expect(result.done == false)
    }

    @Test
    func ignoresBlankAndPreambles() throws {
        #expect(try GoogleClient.parseLine(Data()).delta == nil)
        #expect(try GoogleClient.parseLine(Data("event: anything".utf8)).delta == nil)
    }

    @Test
    func throwsOnMalformedDataJSON() {
        let line = Data("data: not json".utf8)
        #expect(throws: GoogleClientError.self) {
            _ = try GoogleClient.parseLine(line)
        }
    }
}
