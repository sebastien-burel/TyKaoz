import Foundation
import Testing
@testable import TySkaoz

@Suite @MainActor
struct HTTPPluginToolTests {

    private func def(
        method: PluginToolDef.Method = .post,
        urlTemplate: String = "https://api.example.com/echo"
    ) -> PluginToolDef {
        PluginToolDef(
            name: "echo",
            description: "echo",
            inputSchemaJSON: #"{"type":"object"}"#,
            urlTemplate: urlTemplate,
            method: method,
            headers: [:]
        )
    }

    @Test
    func postReturnsResponseBody() async throws {
        let session = MockURLProtocol.session(data: Data(#"{"ok":true}"#.utf8), status: 200)
        let tool = HTTPPluginTool(definition: def(), session: session)
        let output = try await tool.execute(arguments: Data(#"{"q":"hi"}"#.utf8))
        #expect(output.contains("\"ok\":true"))
    }

    @Test
    func nonSuccessStatusThrows() async {
        let session = MockURLProtocol.session(data: Data("boom".utf8), status: 500)
        let tool = HTTPPluginTool(definition: def(), session: session)
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: Data("{}".utf8))
        }
    }

    @Test
    func networkErrorThrows() async {
        let session = MockURLProtocol.session(error: URLError(.notConnectedToInternet))
        let tool = HTTPPluginTool(definition: def(), session: session)
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: Data("{}".utf8))
        }
    }
}
