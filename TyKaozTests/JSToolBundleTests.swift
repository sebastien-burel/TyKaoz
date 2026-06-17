import Foundation
import Testing
@testable import TyKaoz

@MainActor
@Suite(.serialized)
struct JSToolBundleTests {

    @Test
    func exposesAndExecutesDeclaredTool() async throws {
        let bundle = try #require(JSToolBundle(
            script: """
            globalThis.tools = [{
              name: "shout",
              description: "Uppercases text.",
              input_schema: { type: "object", properties: { text: { type: "string" } } },
              run: async function (args) { return args.text.toUpperCase(); }
            }];
            """,
            tools: ToolRegistry(tools: []),
            memory: MemoryStore(fileURL: AgentRuntimeTests.tempURL())))

        #expect(bundle.specs.map(\.name) == ["shout"])
        #expect(bundle.specs.first?.inputSchemaJSON.contains("\"text\"") == true)

        let registry = ToolRegistry(tools: bundle.tools())
        let result = await registry.execute(
            ToolCall(id: "1", toolName: "shout", arguments: Data(#"{"text":"hi"}"#.utf8)))

        #expect(result.isError == false)
        #expect(result.content == "HI")
    }

    @Test
    func jsToolCanCallTheLLM() async throws {
        let bundle = try #require(JSToolBundle(
            script: """
            globalThis.tools = [{
              name: "ask",
              description: "Asks the model.",
              input_schema: { type: "object" },
              run: async function () {
                return await host.llm.chat([{ role: "user", content: "x" }]);
              }
            }];
            """,
            makeProvider: { MockProvider(events: [.textDelta("Bon"), .textDelta("jour")]) },
            tools: ToolRegistry(tools: []),
            memory: MemoryStore(fileURL: AgentRuntimeTests.tempURL())))

        let registry = ToolRegistry(tools: bundle.tools())
        let result = await registry.execute(
            ToolCall(id: "1", toolName: "ask", arguments: Data("{}".utf8)))

        #expect(result.isError == false)
        #expect(result.content == "Bonjour")
    }

    @Test
    func jsToolErrorSurfacesAsToolError() async throws {
        let bundle = try #require(JSToolBundle(
            script: """
            globalThis.tools = [{
              name: "fail",
              description: "Always fails.",
              input_schema: { type: "object" },
              run: async function () { throw new Error("nope"); }
            }];
            """,
            tools: ToolRegistry(tools: []),
            memory: MemoryStore(fileURL: AgentRuntimeTests.tempURL())))

        let registry = ToolRegistry(tools: bundle.tools())
        let result = await registry.execute(
            ToolCall(id: "1", toolName: "fail", arguments: Data("{}".utf8)))

        #expect(result.isError == true)
        #expect(result.content.contains("nope"))
    }
}
