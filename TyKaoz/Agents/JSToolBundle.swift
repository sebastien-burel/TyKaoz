import Foundation
import XSBridgeKit

/// Loads a JavaScript script that declares `globalThis.tools = [{ name,
/// description, input_schema, run: async (args) => … }]` and exposes each entry
/// as a native `Tool`, so a JS-authored tool slots into the existing
/// `ToolRegistry` alongside built-in and HTTP-plugin tools.
///
/// One persistent engine backs the whole bundle (shared by its tools). Tools
/// can themselves reach the LLM, other tools and memory via `host.*`, since the
/// bundle wires the same `TyKaozHostBridge`.
nonisolated final class JSToolBundle: @unchecked Sendable {

    private let engine: XSEngine
    private let bridge: TyKaozHostBridge
    private let lock = NSLock()
    private var waiters: [String: (Result<String, Error>) -> Void] = [:]

    /// The tool specs declared by the script, read once at load.
    let specs: [ToolSpec]

    init?(
        script: String,
        makeProvider: @escaping @Sendable () -> (any LLMProvider)? = { nil },
        tools: ToolRegistry,
        memory: MemoryStore,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        let bridge = TyKaozHostBridge(
            makeProvider: makeProvider, tools: tools, memory: memory, log: log)
        guard let engine = XSEngine(host: bridge) else { return nil }
        self.bridge = bridge
        self.engine = engine

        do {
            _ = try engine.eval(script)
            let specsJSON = try engine.eval(
                "(globalThis.tools||[]).map(function(t){"
                + "return {name:t.name,description:t.description,input_schema:t.input_schema};})")
            self.specs = JSToolBundle.parseSpecs(specsJSON)
        } catch {
            return nil
        }

        bridge.onControl = { [weak self] key, params in
            guard key == "__toolResult" else { return }
            self?.deliver(params)
        }
    }

    /// The native `Tool` wrappers for each declared tool.
    func tools() -> [any Tool] {
        specs.map { JSBackedTool(spec: $0, bundle: self) }
    }

    /// Invoke a declared tool and await its result. Called from `Tool.execute`.
    func call(name: String, argsJSON: String) async throws -> String {
        let callId = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            waiters[callId] = { continuation.resume(with: $0) }
            lock.unlock()

            let invoke = "__callTool("
                + "\(AgentJSON.jsLiteral(name)), "
                + "\(AgentJSON.jsLiteral(argsJSON)), "
                + "\(AgentJSON.jsLiteral(callId)))"
            do {
                _ = try engine.eval(invoke)
            } catch let error as XSError {
                resolveWaiter(callId, .failure(ToolError.execution(message: error.message)))
            } catch {
                resolveWaiter(callId, .failure(error))
            }
        }
    }

    // MARK: - Result delivery

    /// `__toolResult` params: `[callId, resultJSON | null, errorMessage | null]`.
    private func deliver(_ params: [Any]) {
        guard let callId = params.first as? String else { return }
        if params.count > 2, let message = params[2] as? String, !message.isEmpty {
            resolveWaiter(callId, .failure(ToolError.execution(message: message)))
            return
        }
        let raw = (params.count > 1 ? params[1] as? String : nil) ?? "null"
        resolveWaiter(callId, .success(AgentJSON.unwrapResult(raw)))
    }

    private func resolveWaiter(_ id: String, _ result: Result<String, Error>) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: id)
        lock.unlock()
        waiter?(result)
    }

    private static func parseSpecs(_ json: String) -> [ToolSpec] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return array.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let description = (entry["description"] as? String) ?? ""
            let schema = entry["input_schema"].map { AgentJSON.string($0) } ?? "{}"
            return ToolSpec(name: name, description: description, inputSchemaJSON: schema)
        }
    }
}

/// A native `Tool` whose execution is delegated to a JS `run` function in a
/// `JSToolBundle`.
nonisolated struct JSBackedTool: Tool {
    let spec: ToolSpec
    let bundle: JSToolBundle

    func execute(arguments: Data) async throws -> String {
        let argsJSON = String(data: arguments, encoding: .utf8) ?? "{}"
        return try await bundle.call(name: spec.name, argsJSON: argsJSON)
    }
}
