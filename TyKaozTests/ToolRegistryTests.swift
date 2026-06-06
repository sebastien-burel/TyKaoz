import Foundation
import Testing
@testable import TyKaoz

struct ToolRegistryTests {

    @Test
    func registersToolsByName() {
        let registry = ToolRegistry(tools: [CurrentDateTimeTool(), FetchURLTool()])
        #expect(registry.tool(named: "current_datetime") != nil)
        #expect(registry.tool(named: "fetch_url") != nil)
        #expect(registry.tool(named: "nope") == nil)
        #expect(registry.all.count == 2)
        #expect(registry.specs.map(\.name).sorted() == ["current_datetime", "fetch_url"])
    }

    @Test
    func executingUnknownToolReturnsError() async {
        let registry = ToolRegistry(tools: [])
        let result = await registry.execute(ToolCall(id: "a", toolName: "ghost", arguments: Data("{}".utf8)))
        #expect(result.callID == "a")
        #expect(result.isError == true)
        #expect(result.content.contains("Unknown tool"))
    }

    @Test
    func executingSuccessfulToolReturnsContent() async throws {
        let registry = ToolRegistry(tools: [CurrentDateTimeTool()])
        let result = await registry.execute(
            ToolCall(id: "x", toolName: "current_datetime", arguments: Data("{}".utf8))
        )
        #expect(result.callID == "x")
        #expect(result.isError == false)
        // ISO 8601 → starts with year digits
        #expect(result.content.first?.isNumber == true)
    }

    @Test
    func executingFailingToolSurfacesErrorInResult() async {
        let registry = ToolRegistry(tools: [FetchURLTool()])
        // Bad args force the JSON decode to throw inside the tool — should
        // come back as an error result, not propagate.
        let result = await registry.execute(
            ToolCall(id: "y", toolName: "fetch_url", arguments: Data("not-json".utf8))
        )
        #expect(result.callID == "y")
        #expect(result.isError == true)
        #expect(result.content.contains("Arguments invalides"))
    }
}
