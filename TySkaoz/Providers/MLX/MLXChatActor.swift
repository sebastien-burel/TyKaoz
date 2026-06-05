import Foundation
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// One owner of the loaded chat `ModelContainer` per modelID. Like
/// `MLXEmbeddingActor`, isolates Metal-bound work so overlapping
/// `chat()` calls don't interleave on the single command queue.
///
/// Lazy load on first `chat()`. Idle-unload (Phase C3) is wired in
/// a follow-up commit — for now the container lives until the
/// actor itself is dropped.
actor MLXChatActor {
    private static var instances: [String: MLXChatActor] = [:]

    @MainActor
    static func shared(for modelID: String) -> MLXChatActor {
        if let existing = instances[modelID] { return existing }
        let actor = MLXChatActor(modelID: modelID)
        instances[modelID] = actor
        return actor
    }

    let modelID: String
    private var container: ModelContainer?
    private let downloader: any Downloader
    private let tokenizerLoader: any TokenizerLoader

    /// Snapshot of when the last chat() call completed. The
    /// idle-unload task compares against this to decide whether
    /// activity has happened since it was scheduled.
    private var lastUsedAt: Date = .distantPast
    private var idleUnloadTask: Task<Void, Never>?

    /// Default idle threshold before unloading the container. 5
    /// minutes — short enough to feel polite on a 16 GB Mac running
    /// the wiki embedder + a chat model, long enough to absorb a
    /// "I'll come back in a minute" pause without forcing a reload.
    private let idleTimeout: TimeInterval = 5 * 60

    private init(modelID: String) {
        self.modelID = modelID
        self.downloader = #hubDownloader()
        self.tokenizerLoader = #huggingFaceTokenizerLoader()
    }

    // MARK: - Public

    /// Streams one chat round. The returned stream yields
    /// `StreamEvent`s mapped from mlx-swift-lm's `Generation`
    /// stream — `.chunk(text)` → `.textDelta`, `.toolCall` →
    /// `.toolCall` with a UUID id (MLX's ToolCall has no id field;
    /// we synthesise one so our agent loop can route results back).
    func chat(
        messages: [ChatMessage],
        tools: [TySkaoz.ToolSpec]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Cancel any pending unload — fresh activity.
                idleUnloadTask?.cancel()
                idleUnloadTask = nil

                do {
                    let container = try await loadIfNeeded()
                    let userInput = UserInput(
                        chat: Self.mapMessages(messages),
                        tools: tools.isEmpty ? nil : tools.compactMap(Self.mapTool)
                    )
                    let lmInput = try await container.prepare(input: userInput)
                    let params = GenerateParameters(
                        maxTokens: 4096,
                        temperature: 0.7
                    )
                    let stream = try await container.generate(
                        input: lmInput,
                        parameters: params
                    )
                    for await event in stream {
                        if Task.isCancelled { break }
                        switch event {
                        case .chunk(let text):
                            continuation.yield(.textDelta(text))
                        case .toolCall(let call):
                            // MLX `ToolCall` has no id; synthesise
                            // one so TyKaoz's ChatSession can route
                            // results back deterministically.
                            let argsJSON: String
                            if let data = try? JSONEncoder().encode(call.function.arguments),
                               let str = String(data: data, encoding: .utf8) {
                                argsJSON = str
                            } else {
                                argsJSON = "{}"
                            }
                            continuation.yield(.toolCall(
                                id: "mlx-" + UUID().uuidString.prefix(8).lowercased(),
                                name: call.function.name,
                                argumentsJSON: argsJSON
                            ))
                        case .info:
                            // Token throughput / stop reason —
                            // not surfaced upstream yet.
                            break
                        }
                    }
                    lastUsedAt = Date()
                    scheduleIdleUnload()
                    continuation.finish()
                } catch {
                    // Even on failure, kick off the idle countdown
                    // so a stuck container doesn't hold memory if
                    // the user gives up after one bad round.
                    lastUsedAt = Date()
                    scheduleIdleUnload()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Drops the loaded container. Releases GPU buffers + ~few GB
    /// RAM for 4-bit chat models. Called by the idle-unload timer
    /// and exposed publicly so the Phase B settings UI could wire
    /// a manual "décharger" button later if anyone asks.
    func unload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        container = nil
    }

    // MARK: - Idle unload

    /// Starts (or restarts) the idle-unload countdown. The task
    /// snapshots `lastUsedAt` at scheduling time; on wake it
    /// compares against the current value — if anything has used
    /// the actor in the meantime, the snapshot has moved and the
    /// unload is skipped. This way two overlapping schedulings
    /// don't double-unload.
    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        let scheduledAt = lastUsedAt
        let timeoutNanos = UInt64(idleTimeout * 1_000_000_000)
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanos)
            if Task.isCancelled { return }
            await self?.unloadIfStill(scheduledAt: scheduledAt)
        }
    }

    private func unloadIfStill(scheduledAt: Date) {
        guard lastUsedAt == scheduledAt else { return }
        container = nil
        idleUnloadTask = nil
    }

    // MARK: - Internals

    private func loadIfNeeded() async throws -> ModelContainer {
        if let container { return container }
        _ = try await MLXModelStore.shared.download(modelID: modelID)
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: downloader,
            using: tokenizerLoader,
            configuration: ModelConfiguration(id: modelID)
        ) { _ in
            // Load-time progress not surfaced — the download
            // step above already drove the progress bar.
        }
        container = loaded
        await MLXModelStore.shared.touch(modelID: modelID)
        return loaded
    }

    // MARK: - Mapping

    /// Converts TyKaoz's ChatMessage history into MLX's Chat.Message.
    /// Tool calls round-trip best-effort: MLX's Chat.Message has no
    /// dedicated tool-call slot on the assistant role, so we serialise
    /// the call as JSON inside an assistant message. The model's chat
    /// template re-parses this. Tool results map cleanly to `.tool(...)`.
    private static func mapMessages(_ messages: [ChatMessage]) -> [Chat.Message] {
        messages.compactMap { msg in
            switch msg.role {
            case .system:
                return .system(msg.content)
            case .user:
                return .user(msg.content)
            case .assistant:
                return .assistant(msg.content)
            case .toolCall:
                let name = msg.toolName ?? "unknown"
                let body = msg.content.isEmpty ? "{}" : msg.content
                return .assistant("<tool_call>{\"name\":\"\(name)\",\"arguments\":\(body)}</tool_call>")
            case .toolResult:
                return .tool(msg.content)
            }
        }
    }

    /// Wraps a TyKaoz `ToolSpec` in the OpenAI-style schema dict
    /// mlx-swift-lm expects (`{"type": "function", "function": {...}}`).
    /// Returns `nil` if the input JSON schema can't be parsed —
    /// those tools just don't get advertised to the model, rather
    /// than failing the whole turn.
    private static func mapTool(_ spec: TySkaoz.ToolSpec) -> MLXLMCommon.ToolSpec? {
        guard let data = spec.inputSchemaJSON.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let schema = parsed as? [String: Any]
        else { return nil }
        return [
            "type": "function",
            "function": [
                "name": spec.name,
                "description": spec.description,
                "parameters": schema,
            ] as [String: any Sendable],
        ]
    }
}
