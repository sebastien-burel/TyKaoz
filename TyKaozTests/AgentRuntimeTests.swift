import Foundation
import Testing
import XSBridgeKit
@testable import TyKaoz

@MainActor
@Suite(.serialized)
struct AgentRuntimeTests {

    @Test
    func orchestratorDrivesToolLLMAndMemory() async throws {
        let memory = MemoryStore(fileURL: Self.tempURL())
        let logs = LogSink()
        let runtime = AgentRuntime(
            makeProvider: { MockProvider(events: [.textDelta("Bon"), .textDelta("jour")]) },
            tools: ToolRegistry(tools: [EchoTool()]),
            memory: memory,
            log: { logs.append($0) }
        )

        let script = """
        globalThis.run = async function (input) {
          host.log("start", input.name);
          const echoed = await host.tool.call("echo", { text: input.name });
          let streamed = "";
          const full = await host.llm.chat(
            [{ role: "user", content: "hi" }],
            function (d) { streamed += d; });
          const id = await host.memory.save("greeting", echoed + " / " + full);
          return { echoed: echoed, full: full, streamed: streamed, id: id };
        };
        """

        let resultJSON = try await runtime.run(script: script, input: ["name": "Seb"])
        let result = try #require(Self.object(resultJSON))

        #expect(result["echoed"] as? String == "echo:Seb")
        #expect(result["full"] as? String == "Bonjour")
        #expect(result["streamed"] as? String == "Bonjour")     // tokens streamed in order
        #expect((result["id"] as? String).flatMap(UUID.init(uuidString:)) != nil)

        #expect(memory.memories.count == 1)
        #expect(memory.memories.first?.title == "greeting")
        #expect(memory.memories.first?.content == "echo:Seb / Bonjour")
        #expect(logs.all == ["start Seb"])
    }

    @Test
    func orchestratorPropagatesScriptError() async {
        let memory = MemoryStore(fileURL: Self.tempURL())
        let runtime = AgentRuntime(
            makeProvider: { nil }, tools: ToolRegistry(tools: []), memory: memory)

        let script = "globalThis.run = async function () { throw new Error('boom'); };"
        await #expect(throws: AgentError.self) {
            _ = try await runtime.run(script: script)
        }
    }

    @Test
    func unknownToolRejectsAndIsCatchable() async throws {
        let memory = MemoryStore(fileURL: Self.tempURL())
        let runtime = AgentRuntime(
            makeProvider: { nil }, tools: ToolRegistry(tools: []), memory: memory)

        let script = """
        globalThis.run = async function () {
          try { await host.tool.call("ghost", {}); return "no-throw"; }
          catch (e) { return "caught:" + e; }
        };
        """
        let resultJSON = try await runtime.run(script: script)
        #expect(resultJSON.contains("caught:"))
        #expect(resultJSON.contains("Unknown tool"))
    }

    /// The agent runs in module goal: it can `import ... from` a library file and
    /// export `run` (the idiomatic contract).
    @Test
    func agentImportsLibraryModule() async throws {
        let libs = FileManager.default.temporaryDirectory
            .appending(path: "tykaoz-libs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: libs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: libs) }
        try "export const greet = (name) => `Demat, ${name}!`;\n"
            .write(to: libs.appending(path: "greet.js"), atomically: true, encoding: .utf8)

        let memory = MemoryStore(fileURL: Self.tempURL())
        let runtime = AgentRuntime(
            makeProvider: { nil }, tools: ToolRegistry(tools: []), memory: memory)

        let script = """
        import { greet } from "./greet.js";
        export async function run(input) { return greet(input.name); }
        """
        let resultJSON = try await runtime.run(
            script: script, input: ["name": "Seb"], libraryRoot: libs)
        #expect(resultJSON == "\"Demat, Seb!\"")
    }

    /// XSBridgeKit invariant: every resolve/reject/onToken root is balanced and
    /// no async call is left pending once the work settles (no slot leak).
    @Test
    func bridgeBalancesRootsAfterCalls() async throws {
        let memory = MemoryStore(fileURL: Self.tempURL())
        let bridge = TyKaozHostBridge(
            makeProvider: { MockProvider(events: [.textDelta("a"), .textDelta("b")]) },
            tools: ToolRegistry(tools: [EchoTool()]),
            memory: memory,
            resolver: ModuleResolver(entrySource: "", root: nil))
        let engine = try #require(XSEngine(host: bridge))

        let metrics = try await Task.detached { () -> (Int, UInt32, UInt32) in
            _ = try engine.eval("""
            host.tool.call("echo", { text: "x" }).then(function (r) { globalThis.a = r; });
            host.llm.chat([{ role: "user", content: "hi" }], function () {})
              .then(function (r) { globalThis.b = r; });
            host.memory.save("t", "c").then(function (r) { globalThis.c = r; });
            """)
            engine.runUntilIdle(timeout: 5)
            let counts = engine.rememberForgetCounts
            return (engine.pendingCount, counts.0, counts.1)
        }.value

        #expect(metrics.0 == 0)          // nothing pending
        #expect(metrics.1 == metrics.2)  // remembered == forgotten
    }

    // MARK: - Helpers

    static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "tykaoz-agent-tests-\(UUID().uuidString).json")
    }

    static func object(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// A trivial tool that echoes its `text` argument. Used to exercise tool
/// dispatch from JS without any real side effect.
struct EchoTool: Tool {
    let spec = ToolSpec(
        name: "echo",
        description: "Echoes the provided text.",
        inputSchemaJSON: #"{"type":"object","properties":{"text":{"type":"string"}}}"#)

    private struct Args: Decodable { let text: String? }

    func execute(arguments: Data) async throws -> String {
        let args = try? JSONDecoder().decode(Args.self, from: arguments)
        return "echo:" + (args?.text ?? "")
    }
}

/// Thread-safe sink for the agent `host.log` output (called off the main thread).
final class LogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock(); lines.append(line); lock.unlock()
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }
}
