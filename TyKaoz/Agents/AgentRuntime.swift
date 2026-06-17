import Foundation
import XSBridgeKit

enum AgentError: Error, LocalizedError {
    case engineCreationFailed
    case evaluation(String)
    /// The agent's own `run(input)` threw or rejected.
    case script(String)
    /// The agent did not settle within its time budget.
    case timeout

    var errorDescription: String? {
        switch self {
        case .engineCreationFailed: return "Impossible de créer le moteur JavaScript."
        case .evaluation(let m):    return "Erreur d'évaluation : \(m)"
        case .script(let m):        return m
        case .timeout:              return "L'agent n'a pas terminé dans le délai imparti."
        }
    }
}

/// Runs a standalone JavaScript agent: a script that defines
/// `async function run(input) { … }` and drives the LLM, tools and memory
/// through `host.*`. One engine per run, torn down when the agent finishes.
///
/// The script's final value (or thrown error) is reported via the bridge's
/// `__finish` / `__fail` control channel; `run` returns the result as a JSON
/// string (e.g. a string result comes back JSON-quoted).
nonisolated final class AgentRuntime {

    private let makeProvider: @Sendable () -> (any LLMProvider)?
    private let tools: ToolRegistry
    private let memory: MemoryStore
    private let log: @Sendable (String) -> Void

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

    func run(script: String, input: Any? = nil, timeout: TimeInterval = 10) async throws -> String {
        let bridge = TyKaozHostBridge(
            makeProvider: makeProvider, tools: tools, memory: memory, log: log)
        return try await withCheckedThrowingContinuation { continuation in
            let session = AgentSession(bridge: bridge, continuation: continuation)
            session.start(script: script, input: input, timeout: timeout)
        }
    }
}

/// Owns one engine + bridge for the lifetime of a single agent run. Retains
/// itself until the continuation is resumed, then releases the engine off the
/// XS thread (its deinit joins that thread, so it must not run on it).
private nonisolated final class AgentSession {

    private let bridge: TyKaozHostBridge
    private var engine: XSEngine?
    private var continuation: CheckedContinuation<String, Error>?
    private var selfRef: AgentSession?
    private var timeoutItem: DispatchWorkItem?
    private let lock = NSLock()

    init(bridge: TyKaozHostBridge, continuation: CheckedContinuation<String, Error>) {
        self.bridge = bridge
        self.continuation = continuation
    }

    func start(script: String, input: Any?, timeout: TimeInterval) {
        selfRef = self

        let timeoutItem = DispatchWorkItem { [weak self] in
            self?.complete(.failure(AgentError.timeout))
        }
        self.timeoutItem = timeoutItem
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
        bridge.onControl = { [weak self] key, params in
            switch key {
            case "__finish": self?.complete(.success(AgentSession.first(params)))
            case "__fail":   self?.complete(.failure(AgentError.script(AgentSession.first(params))))
            default:         break
            }
        }

        guard let engine = XSEngine(host: bridge) else {
            complete(.failure(AgentError.engineCreationFailed))
            return
        }
        self.engine = engine

        do {
            _ = try engine.eval(script)
            let inputJSON = AgentJSON.string(input ?? NSNull())
            _ = try engine.eval("__runAgent(\(AgentJSON.jsLiteral(inputJSON)))")
        } catch let error as XSError {
            complete(.failure(AgentError.evaluation(error.message)))
        } catch {
            complete(.failure(error))
        }
    }

    /// Resume the continuation at most once, then tear down.
    private func complete(_ result: Result<String, Error>) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        let engine = self.engine
        self.engine = nil
        lock.unlock()

        timeoutItem?.cancel()
        timeoutItem = nil
        continuation.resume(with: result)
        bridge.onControl = nil

        // Release the engine off the XS thread: its deinit stops and joins that
        // thread, which would deadlock if we ran it on that thread (we may be on
        // it now, when __finish fired). Drain the run loop first so the control
        // call's own settle is applied before the machine is deleted, then drop
        // the last reference on a global-queue thread.
        if let engine {
            DispatchQueue.global().async {
                engine.runUntilIdle(timeout: 2)
                withExtendedLifetime(engine) {}
            }
        }
        selfRef = nil
    }

    /// The first param of a control call (the result/error JSON the prelude
    /// produced with `JSON.stringify`); empty string if absent.
    private static func first(_ params: [Any]) -> String {
        (params.first as? String) ?? ""
    }
}
