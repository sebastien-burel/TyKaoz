import Foundation
import XSBridgeKit

/// Bridges a running JS agent to TyKaoz's capabilities. The XS engine only
/// provides the `__nativeCall` / `__nativeCallSync` primitives; this type's
/// `prelude` installs the ergonomic `host.*` wrappers and `handle` routes each
/// call by key to the LLM provider, the tool registry, or the memory store.
///
/// Concurrency: `handle` / `handleSync` run on the engine's private XS thread
/// (never the main thread). Anything touching `@MainActor` state (the memory
/// store) hops via `Task { @MainActor in … }`; the `HostResponder` is
/// thread-safe and wakes the engine's run loop to settle the JS promise. We
/// never block the XS thread on the main actor.
nonisolated final class TyKaozHostBridge: HostBridge {

    private let makeProvider: @Sendable () -> (any LLMProvider)?
    private let tools: ToolRegistry
    private let memory: MemoryStore
    private let log: @Sendable (String) -> Void

    /// Control channel for `__`-prefixed keys (e.g. `__finish`, `__toolResult`).
    /// Set once by the owning runtime before any script runs, so no real race.
    nonisolated(unsafe) var onControl: ((String, [Any]) -> Void)?

    init(
        makeProvider: @escaping @Sendable () -> (any LLMProvider)?,
        tools: ToolRegistry,
        memory: MemoryStore,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.makeProvider = makeProvider
        self.tools = tools
        self.memory = memory
        self.log = log
    }

    // MARK: - Prelude

    var prelude: String {
        """
        globalThis.host = {
          llm: {
            chat: function (messages, onToken) {
              return new Promise(function (res, rej) {
                __nativeCall('llm.chat', [messages], res, rej, onToken);
              });
            }
          },
          tool: {
            list: function () {
              return new Promise(function (res, rej) {
                __nativeCall('tool.list', [], res, rej);
              });
            },
            call: function (name, args) {
              return new Promise(function (res, rej) {
                __nativeCall('tool.call', [name, args || {}], res, rej);
              });
            }
          },
          memory: {
            save: function (title, content) {
              return new Promise(function (res, rej) {
                __nativeCall('memory.save', [title, content], res, rej);
              });
            },
            list: function () {
              return new Promise(function (res, rej) {
                __nativeCall('memory.list', [], res, rej);
              });
            },
            read: function (id) {
              return new Promise(function (res, rej) {
                __nativeCall('memory.read', [id], res, rej);
              });
            }
          },
          log: function () {
            var args = Array.prototype.slice.call(arguments);
            return __nativeCallSync('log', args);
          }
        };

        // Orchestrator entry: runs globalThis.run(input) and reports the result.
        globalThis.__runAgent = function (inputJSON) {
          Promise.resolve()
            .then(function () { return globalThis.run(JSON.parse(inputJSON)); })
            .then(function (r) {
              __nativeCall('__finish', [JSON.stringify(r === undefined ? null : r)],
                           function () {}, function () {});
            })
            .catch(function (e) {
              __nativeCall('__fail', [String((e && e.stack) || e)],
                           function () {}, function () {});
            });
        };

        // JS-tool entry: invokes a declared tool by name and reports its result.
        globalThis.__callTool = function (name, argsJSON, callId) {
          var list = globalThis.tools || [];
          var tool = list.find(function (t) { return t.name === name; });
          if (!tool || typeof tool.run !== 'function') {
            __nativeCall('__toolResult', [callId, null, 'unknown tool: ' + name],
                         function () {}, function () {});
            return;
          }
          Promise.resolve()
            .then(function () { return tool.run(JSON.parse(argsJSON)); })
            .then(function (r) {
              __nativeCall('__toolResult',
                           [callId, JSON.stringify(r === undefined ? null : r), null],
                           function () {}, function () {});
            })
            .catch(function (e) {
              __nativeCall('__toolResult',
                           [callId, null, String((e && e.stack) || e)],
                           function () {}, function () {});
            });
        };
        """
    }

    // MARK: - Async dispatch

    func handle(key: String, paramsJSON: String, responder: HostResponder) {
        let params = AgentJSON.params(paramsJSON)

        // Control keys are handled by the owning runtime; settle cleanly.
        if key.hasPrefix("__") {
            onControl?(key, params)
            responder.resolve("null")
            return
        }

        switch key {
        case "llm.chat":
            handleChat(params: params, responder: responder)
        case "tool.list":
            handleToolList(responder: responder)
        case "tool.call":
            handleToolCall(params: params, responder: responder)
        case "memory.save":
            handleMemorySave(params: params, responder: responder)
        case "memory.read":
            handleMemoryRead(params: params, responder: responder)
        case "memory.list":
            handleMemoryList(responder: responder)
        default:
            responder.reject(AgentJSON.string("unknown host call: \(key)"))
        }
    }

    func handleSync(key: String, paramsJSON: String) -> String {
        switch key {
        case "log":
            let parts = AgentJSON.params(paramsJSON).map { stringify($0) }
            log(parts.joined(separator: " "))
            return "null"
        default:
            return "null"
        }
    }

    // MARK: - Handlers

    private func handleChat(params: [Any], responder: HostResponder) {
        guard let provider = makeProvider() else {
            responder.reject(AgentJSON.string("no LLM provider configured"))
            return
        }
        let messages = AgentJSON.decodeMessages(params.first)
        // `chat` is main-actor-isolated (it sets up the stream); the streamed
        // iteration suspends, so the main actor stays free, and the responder
        // is thread-safe.
        Task { @MainActor in
            do {
                var full = ""
                for try await event in provider.chat(messages: messages, tools: []) {
                    if case .textDelta(let delta) = event {
                        full += delta
                        responder.emit(AgentJSON.string(delta))
                    }
                }
                responder.resolve(AgentJSON.string(full))
            } catch {
                responder.reject(AgentJSON.string(error.localizedDescription))
            }
        }
    }

    private func handleToolList(responder: HostResponder) {
        let tools = self.tools
        // `ToolRegistry`/`Tool` are main-actor-isolated; read their specs there.
        Task { @MainActor in responder.resolve(Self.toolListJSON(tools)) }
    }

    private func handleToolCall(params: [Any], responder: HostResponder) {
        guard let name = params.first as? String else {
            responder.reject(AgentJSON.string("tool.call expects [name, args]"))
            return
        }
        let argsJSON = params.count > 1 ? AgentJSON.string(params[1]) : "{}"
        let tools = self.tools
        Task { @MainActor in
            let result = await tools.execute(
                ToolCall(id: UUID().uuidString, toolName: name, arguments: Data(argsJSON.utf8))
            )
            if result.isError {
                responder.reject(AgentJSON.string(result.content))
            } else {
                responder.resolve(AgentJSON.string(result.content))
            }
        }
    }

    private func handleMemorySave(params: [Any], responder: HostResponder) {
        let title = (params.first as? String) ?? ""
        let content = (params.count > 1 ? params[1] as? String : nil) ?? ""
        let memory = self.memory
        Task { @MainActor in
            let saved = memory.add(title: title, content: content)
            responder.resolve(AgentJSON.string(saved.id.uuidString))
        }
    }

    private func handleMemoryRead(params: [Any], responder: HostResponder) {
        guard let idString = params.first as? String, let id = UUID(uuidString: idString) else {
            responder.reject(AgentJSON.string("memory.read expects a valid id"))
            return
        }
        let memory = self.memory
        Task { @MainActor in
            guard let found = memory.memory(id: id) else {
                responder.resolve("null")
                return
            }
            responder.resolve(AgentJSON.string([
                "id": found.id.uuidString,
                "title": found.title,
                "content": found.content
            ]))
        }
    }

    private func handleMemoryList(responder: HostResponder) {
        let memory = self.memory
        Task { @MainActor in
            let list = memory.memories.map { ["id": $0.id.uuidString, "title": $0.title] }
            responder.resolve(AgentJSON.string(list))
        }
    }

    // MARK: - Sync helpers

    @MainActor
    private static func toolListJSON(_ tools: ToolRegistry) -> String {
        let entries: [[String: Any]] = tools.specs.map { spec in
            var schema: Any = [:]
            if let data = spec.inputSchemaJSON.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                schema = parsed
            }
            return ["name": spec.name, "description": spec.description, "input_schema": schema]
        }
        return AgentJSON.string(entries)
    }

    private func stringify(_ value: Any) -> String {
        if let s = value as? String { return s }
        return AgentJSON.string(value)
    }
}
