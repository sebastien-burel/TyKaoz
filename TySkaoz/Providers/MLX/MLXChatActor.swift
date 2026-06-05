import Foundation
import MLXLMCommon
import MLXLLM
import MLXVLM
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
                    // Stateful intercept layer for Gemma 4. MLX's
                    // GemmaFunctionParser targets the Gemma 3
                    // tokens (`<start_function_call>`,
                    // `<end_function_call>`, `<escape>`); Gemma 4
                    // ships different ones (`<|tool_call>`,
                    // `<tool_call|>`, `<|"|>`). Until mlx-swift-lm
                    // catches up we splice in a tiny parser.
                    let needsGemma4 = modelID.localizedCaseInsensitiveContains("gemma-4")
                        || modelID.localizedCaseInsensitiveContains("gemma4")
                    var gemma4Buffer = ""
                    var inGemma4Call = false

                    for await event in stream {
                        if Task.isCancelled { break }
                        switch event {
                        case .chunk(let text):
                            if needsGemma4 {
                                Self.processGemma4Chunk(
                                    text,
                                    buffer: &gemma4Buffer,
                                    inCall: &inGemma4Call,
                                    continuation: continuation
                                )
                            } else {
                                continuation.yield(.textDelta(text))
                            }
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
                    if needsGemma4, !gemma4Buffer.isEmpty {
                        // Flush whatever remains: either a leftover
                        // half-marker that turned out to be literal
                        // text, or a malformed tool call. Emit as
                        // text so we don't swallow content.
                        continuation.yield(.textDelta(gemma4Buffer))
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

        // Route on the catalog flag: VLM entries go through
        // VLMModelFactory (which knows about vision towers +
        // image processors), text-only chat through LLMModelFactory.
        // Custom (off-catalog) IDs default to LLM — covers the
        // common case and gives a clear error otherwise.
        let isVision = MLXModelCatalog.entry(forID: modelID)?.isVision ?? false
        let config = ModelConfiguration(id: modelID)
        let loaded: ModelContainer
        if isVision {
            loaded = try await VLMModelFactory.shared.loadContainer(
                from: downloader,
                using: tokenizerLoader,
                configuration: config
            ) { _ in }
        } else {
            loaded = try await LLMModelFactory.shared.loadContainer(
                from: downloader,
                using: tokenizerLoader,
                configuration: config
            ) { _ in }
        }
        // mlx-swift-lm's `infer(from: model_type)` only recognises
        // exact "gemma" — Gemma 3/4 ship config.json with model_type
        // "gemma4" (or "gemma3", "gemma3_text", …), so the tool-call
        // format silently falls back to `.json`. Result: the model
        // emits its native `call:name{key:value}` envelope as raw
        // text and we relay it as `.textDelta`. Fix it explicitly
        // for the Gemma family.
        if modelID.localizedCaseInsensitiveContains("gemma") {
            await loaded.update { ctx in
                ctx.configuration.toolCallFormat = .gemma
            }
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

    /// Streaming-aware Gemma 4 tool-call detector. MLX's built-in
    /// `GemmaFunctionParser` targets Gemma 3's tokens; this routine
    /// catches the Gemma 4 envelope (`<|tool_call>call:NAME{ARGS}
    /// <tool_call|>` with `<|"|>STR<|"|>` for strings) and emits
    /// `.toolCall` events alongside the surrounding text.
    ///
    /// Invariants:
    /// - When `inCall == false`, `buffer` holds only the tail of
    ///   the stream that might still be a partial open marker.
    ///   Everything safely past it is already emitted as `.textDelta`.
    /// - When `inCall == true`, `buffer` holds the entire span from
    ///   the open marker forward, waiting for the close marker so
    ///   the payload can be parsed atomically.
    private static func processGemma4Chunk(
        _ text: String,
        buffer: inout String,
        inCall: inout Bool,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        // Gemma 4 emits at least two open markers in practice:
        // - `<|tool_call>` paired with the gemma envelope (`call:n{...}`)
        // - `<tool_call>` paired with a malformed-JSON envelope
        //   (`{"name":"…","arguments":{"k:<|"|>v<|"|>}}`).
        // Both close with `<tool_call|>` (pipe before `>`), which
        // makes the close marker our reliable demarcator.
        let openMarkers = ["<|tool_call>", "<tool_call>"]
        let closeMarker = "<tool_call|>"
        buffer += text

        // Process the buffer repeatedly until no transition is
        // possible (handles edge cases like multiple tool calls or
        // a tool call sandwiched between text in one chunk).
        // Used for the "safe tail to hold back" math.
        let maxOpenLen = openMarkers.map(\.count).max() ?? 0

        while true {
            if inCall {
                guard let closeRange = buffer.range(of: closeMarker) else {
                    return
                }
                // Strip whichever open marker is at the buffer start.
                var payloadStart = buffer.startIndex
                for marker in openMarkers where buffer.hasPrefix(marker) {
                    payloadStart = buffer.index(buffer.startIndex, offsetBy: marker.count)
                    break
                }
                let payload = String(buffer[payloadStart..<closeRange.lowerBound])
                if let parsed = parseGemma4Payload(payload) {
                    continuation.yield(.toolCall(
                        id: "mlx-" + UUID().uuidString.prefix(8).lowercased(),
                        name: parsed.name,
                        argumentsJSON: parsed.argumentsJSON
                    ))
                } else {
                    let raw = String(buffer[..<closeRange.upperBound])
                    continuation.yield(.textDelta(raw))
                }
                buffer = String(buffer[closeRange.upperBound...])
                inCall = false
            } else {
                // Pick the earliest open marker in the buffer.
                var earliest: (Range<String.Index>, String)? = nil
                for marker in openMarkers {
                    if let range = buffer.range(of: marker) {
                        if earliest == nil || range.lowerBound < earliest!.0.lowerBound {
                            earliest = (range, marker)
                        }
                    }
                }
                if let (openRange, _) = earliest {
                    let prefix = String(buffer[..<openRange.lowerBound])
                    if !prefix.isEmpty {
                        continuation.yield(.textDelta(prefix))
                    }
                    buffer = String(buffer[openRange.lowerBound...])
                    inCall = true
                } else {
                    // Hold back the longest possible open-marker
                    // suffix so a split-across-chunks marker isn't
                    // missed.
                    if buffer.count > maxOpenLen {
                        let safeEnd = buffer.index(buffer.endIndex, offsetBy: -maxOpenLen)
                        let safe = String(buffer[..<safeEnd])
                        if !safe.isEmpty {
                            continuation.yield(.textDelta(safe))
                        }
                        buffer = String(buffer[safeEnd...])
                    }
                    return
                }
            }
        }
    }

    /// Test-only re-export so unit tests can hit the parser
    /// without going through the full streaming loop.
    static func parseGemma4PayloadForTests(_ payload: String) -> (name: String, argumentsJSON: String)? {
        parseGemma4Payload(payload)
    }

    /// Parses a Gemma 4 call payload. Tries the canonical
    /// `call:name{...}` shape first, then the malformed-JSON shape
    /// the model sometimes emits: `{"name":"…","arguments":{"k:<|"|>
    /// v<|"|>}}` (note the missing closing quote on keys + the
    /// `<|"|>` escape marker for string values).
    private static func parseGemma4Payload(_ payload: String) -> (name: String, argumentsJSON: String)? {
        if let result = parseGemma4CallStyle(payload) { return result }
        if let result = parseGemma4JSONStyle(payload) { return result }
        return nil
    }

    /// Canonical Gemma 4 shape: `call:name{key:value, key:<|"|>str<|"|>}`.
    private static func parseGemma4CallStyle(_ payload: String) -> (name: String, argumentsJSON: String)? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("call:") else { return nil }
        let afterCall = trimmed.dropFirst("call:".count)
        guard let openBrace = afterCall.firstIndex(of: "{"),
              let closeBrace = afterCall.lastIndex(of: "}"),
              closeBrace > openBrace
        else { return nil }

        let name = String(afterCall[..<openBrace])
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        let argsBody = String(afterCall[afterCall.index(after: openBrace)..<closeBrace])
        let escape = "<|\"|>"

        // Tokenise the args body into "key:value" segments. Strings
        // are wrapped in the `<|"|>` escape marker and may contain
        // commas, so we can't naively split on commas.
        var args: [String: Any] = [:]
        var remaining = argsBody[...]
        while !remaining.isEmpty {
            // Trim leading whitespace / commas.
            while let first = remaining.first, first == "," || first.isWhitespace {
                remaining = remaining.dropFirst()
            }
            guard let colon = remaining.firstIndex(of: ":") else { break }
            let key = String(remaining[..<colon])
                .trimmingCharacters(in: .whitespaces)
            remaining = remaining[remaining.index(after: colon)...]

            if remaining.hasPrefix(escape) {
                // Quoted string between escape markers.
                let afterOpen = remaining.dropFirst(escape.count)
                guard let endRange = afterOpen.range(of: escape) else { break }
                let value = String(afterOpen[..<endRange.lowerBound])
                args[key] = value
                remaining = afterOpen[endRange.upperBound...]
            } else {
                // Bare value until the next comma.
                let endIdx = remaining.firstIndex(of: ",") ?? remaining.endIndex
                let raw = String(remaining[..<endIdx])
                    .trimmingCharacters(in: .whitespaces)
                // Best-effort type coercion: number, bool, else string.
                if let i = Int(raw) {
                    args[key] = i
                } else if let d = Double(raw) {
                    args[key] = d
                } else if raw == "true" {
                    args[key] = true
                } else if raw == "false" {
                    args[key] = false
                } else {
                    args[key] = raw
                }
                remaining = endIdx == remaining.endIndex ? "" : remaining[remaining.index(after: endIdx)...]
            }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: args),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return (name, json)
    }

    /// JSON-ish shape Gemma 4 sometimes emits:
    ///   `{"name":"foo","arguments":{"k:<|"|>v<|"|>,"k2":42}}`
    /// Notable malformations the model produces in this mode:
    /// - Keys lose their closing quote before `:` (e.g. `"k:` not `"k":`).
    /// - String values are wrapped in `<|"|>…<|"|>` instead of `"…"`.
    /// We patch both back into valid JSON, then parse normally.
    private static func parseGemma4JSONStyle(_ payload: String) -> (name: String, argumentsJSON: String)? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("\"name\"") else { return nil }

        // Step 1: replace `<|"|>X<|"|>` with `"X"`, JSON-escaping
        // backslashes and quotes inside X so they don't break the
        // resulting JSON. Done with a hand-walk because the marker
        // contains characters that complicate Regex.
        var fixed = ""
        var rest = trimmed[...]
        let escape = "<|\"|>"
        while let open = rest.range(of: escape) {
            fixed.append(contentsOf: rest[..<open.lowerBound])
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.range(of: escape) else {
                // Unterminated escape — give up.
                return nil
            }
            let raw = String(afterOpen[..<close.lowerBound])
            let escaped = raw
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            fixed.append("\"")
            fixed.append(escaped)
            fixed.append("\"")
            rest = afterOpen[close.upperBound...]
        }
        fixed.append(contentsOf: rest)

        // Step 2: fix keys that look like `"q:` (no closing quote
        // before the colon). Insert it.
        // Pattern: `"`, then word chars, then `:` not preceded by `"`.
        let keyFixRegex = #/"([A-Za-z_][A-Za-z0-9_]*):/#
        fixed = fixed.replacing(keyFixRegex) { match in
            "\"\(match.output.1)\":"
        }

        // Step 3: parse as JSON.
        guard let data = fixed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String,
              !name.isEmpty,
              let arguments = object["arguments"] as? [String: Any]
        else { return nil }

        guard let argsData = try? JSONSerialization.data(withJSONObject: arguments),
              let argsJSON = String(data: argsData, encoding: .utf8)
        else { return nil }
        return (name, argsJSON)
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
