import Foundation
import Testing
@testable import TySkaoz

@Suite @MainActor
struct BraveSearchToolTests {

    private func args(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private let sample = #"""
    {"web":{"results":[
      {"title":"Rennes","url":"https://en.wikipedia.org/wiki/Rennes","description":"Capitale de la Bretagne"},
      {"title":"Brocéliande","url":"https://example.com/broceliande","description":"Forêt légendaire"}
    ]}}
    """#

    @Test
    func formatsResults() async throws {
        let session = MockURLProtocol.session(data: Data(sample.utf8), status: 200)
        let tool = BraveSearchTool(apiKey: "token", session: session)
        let output = try await tool.execute(arguments: args(["query": "rennes"]))
        #expect(output.contains("Rennes"))
        #expect(output.contains("https://en.wikipedia.org/wiki/Rennes"))
        #expect(output.contains("Capitale de la Bretagne"))
    }

    @Test
    func missingKeyThrows() async {
        let tool = BraveSearchTool(apiKey: "")
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: self.args(["query": "x"]))
        }
    }

    @Test
    func emptyQueryThrows() async {
        let session = MockURLProtocol.session(data: Data(sample.utf8), status: 200)
        let tool = BraveSearchTool(apiKey: "token", session: session)
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: self.args(["query": "  "]))
        }
    }

    @Test
    func noResultsReported() async throws {
        let session = MockURLProtocol.session(data: Data(#"{"web":{"results":[]}}"#.utf8), status: 200)
        let tool = BraveSearchTool(apiKey: "token", session: session)
        let output = try await tool.execute(arguments: args(["query": "zzz"]))
        #expect(output == "Aucun résultat.")
    }
}
