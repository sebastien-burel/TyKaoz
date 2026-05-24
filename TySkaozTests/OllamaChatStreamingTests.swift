import Foundation
import Testing
@testable import TySkaoz

@Suite(.serialized) @MainActor
struct OllamaChatStreamingTests {
    private let baseURL = URL(string: "http://localhost:11434")!

    // MARK: parseChunk (pure unit tests)

    @Test
    func parsesContentDelta() throws {
        let line = Data(#"{"message":{"role":"assistant","content":"Bonjour"},"done":false}"#.utf8)
        let result = try OllamaClient.parseChunk(line: line)
        #expect(result.delta == "Bonjour")
        #expect(result.done == false)
    }

    @Test
    func parsesDoneSignal() throws {
        let line = Data(#"{"message":{"role":"assistant","content":""},"done":true}"#.utf8)
        let result = try OllamaClient.parseChunk(line: line)
        #expect(result.delta == nil)
        #expect(result.done == true)
    }

    @Test
    func parsesEmptyLineAsNoOp() throws {
        let result = try OllamaClient.parseChunk(line: Data())
        #expect(result.delta == nil)
        #expect(result.done == false)
    }

    @Test
    func throwsOnMalformedJSON() {
        let line = Data("not json".utf8)
        #expect(throws: OllamaClientError.self) {
            _ = try OllamaClient.parseChunk(line: line)
        }
    }

    // Note: HTTP-level errors on chat() are exercised end-to-end through
    // ChatSession.surfacesFailure (with a stub stream) and OllamaClient's
    // listModels variant (with data(for:) mock). The chat() integration
    // against bytes(for:) is verified via manual run against a real server,
    // because URLProtocol mocks do not interact cleanly with AsyncBytes.
}
