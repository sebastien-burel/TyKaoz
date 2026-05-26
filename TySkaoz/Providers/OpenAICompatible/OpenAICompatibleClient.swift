import Foundation

enum OpenAICompatibleError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case network(message: String)
    case http(status: Int, body: String? = nil)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Clé API manquante."
        case .network(let msg):
            return "Erreur réseau : \(msg)"
        case .http(let status, let body):
            if let body, !body.isEmpty {
                return "Réponse HTTP \(status) : \(body)"
            }
            return "Réponse HTTP \(status)."
        case .decoding(let msg):
            return "Réponse inattendue : \(msg)"
        }
    }
}

/// Generic HTTP client for any provider that exposes the OpenAI v1 chat
/// completions API (Mistral, OpenAI, DeepSeek, ...). The auth header is a
/// Bearer token by default; specific providers can subclass / wrap if they
/// need something different.
struct OpenAICompatibleClient {
    let baseURL: URL
    let apiKey: String
    let session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - List models

    func listModels() async throws -> [OpenAICompatibleModelsResponse.Model] {
        var request = URLRequest(url: baseURL.appending(path: "/models"))
        request.timeoutInterval = 10
        request.setValue(
            "Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))",
            forHTTPHeaderField: "Authorization"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw OpenAICompatibleError.network(message: urlError.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleError.network(message: "réponse non-HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAICompatibleError.http(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(OpenAICompatibleModelsResponse.self, from: data).data
        } catch {
            throw OpenAICompatibleError.decoding(message: error.localizedDescription)
        }
    }

    // MARK: - Chat (streaming)

    func chat(
        model: String,
        messages: [ChatMessage],
        tools: [ToolSpec]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appending(path: "/chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(
                        "Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))",
                        forHTTPHeaderField: "Authorization"
                    )
                    request.timeoutInterval = 60
                    request.httpBody = try Self.buildBody(model: model, messages: messages, tools: tools)

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await session.bytes(for: request)
                    } catch let urlError as URLError {
                        throw OpenAICompatibleError.network(message: urlError.localizedDescription)
                    }

                    guard let http = response as? HTTPURLResponse else {
                        throw OpenAICompatibleError.network(message: "réponse non-HTTP")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        // Read the body so the user sees what the provider
                        // actually complained about (DeepSeek/OpenAI/Mistral
                        // all return JSON error bodies with details).
                        var body = ""
                        for try await byte in bytes {
                            body.append(Character(UnicodeScalar(byte)))
                            if body.count > 1500 { break }
                        }
                        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                        throw OpenAICompatibleError.http(
                            status: http.statusCode,
                            body: trimmed.isEmpty ? nil : trimmed
                        )
                    }

                    // Accumulators for tool-call deltas, keyed by the
                    // provider-assigned `index`. We only emit a complete
                    // .toolCall event once the finish_reason arrives.
                    var accumulators: [Int: (id: String, name: String, args: String)] = [:]

                    func flushToolCalls() {
                        for index in accumulators.keys.sorted() {
                            let acc = accumulators[index]!
                            continuation.yield(.toolCall(
                                id: acc.id,
                                name: acc.name,
                                argumentsJSON: acc.args
                            ))
                        }
                        accumulators.removeAll()
                    }

                    func absorb(_ info: LineInfo) {
                        if let delta = info.textDelta {
                            continuation.yield(.textDelta(delta))
                        }
                        if let reasoning = info.reasoningDelta {
                            continuation.yield(.reasoningDelta(reasoning))
                        }
                        for tcDelta in info.toolCallDeltas {
                            let index = tcDelta.index ?? 0
                            if var acc = accumulators[index] {
                                if let id = tcDelta.id, acc.id.isEmpty { acc.id = id }
                                if let name = tcDelta.name, acc.name.isEmpty { acc.name = name }
                                if let argsDelta = tcDelta.argumentsDelta { acc.args += argsDelta }
                                accumulators[index] = acc
                            } else {
                                accumulators[index] = (
                                    id: tcDelta.id ?? "",
                                    name: tcDelta.name ?? "",
                                    args: tcDelta.argumentsDelta ?? ""
                                )
                            }
                        }
                    }

                    var buffer = Data()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A {
                            let info = try Self.parseLine(buffer)
                            buffer.removeAll(keepingCapacity: true)
                            absorb(info)
                            if info.done {
                                flushToolCalls()
                                continuation.finish()
                                return
                            }
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty {
                        let info = try Self.parseLine(buffer)
                        absorb(info)
                    }
                    flushToolCalls()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Parsing one SSE line

    /// What `parseLine` returns: text delta if any, tool-call deltas if any,
    /// and the `done` flag (sentinel `[DONE]` or `finish_reason != nil`).
    struct LineInfo: Equatable {
        let textDelta: String?
        let toolCallDeltas: [ToolCallDeltaInfo]
        let reasoningDelta: String?
        let done: Bool

        struct ToolCallDeltaInfo: Equatable {
            let index: Int?
            let id: String?
            let name: String?
            let argumentsDelta: String?
        }
    }

    /// Parses one SSE line. Blank lines, `event:` and `id:` preambles are
    /// no-ops. `data: [DONE]` flips `done`. Malformed JSON in a `data:`
    /// payload throws.
    static func parseLine(_ raw: Data) throws -> LineInfo {
        guard let line = String(data: raw, encoding: .utf8) else {
            return LineInfo(textDelta: nil, toolCallDeltas: [], reasoningDelta: nil, done: false)
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return LineInfo(textDelta: nil, toolCallDeltas: [], reasoningDelta: nil, done: false) }
        guard trimmed.hasPrefix("data:") else { return LineInfo(textDelta: nil, toolCallDeltas: [], reasoningDelta: nil, done: false) }

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return LineInfo(textDelta: nil, toolCallDeltas: [], reasoningDelta: nil, done: true)
        }
        guard let data = payload.data(using: .utf8) else {
            return LineInfo(textDelta: nil, toolCallDeltas: [], reasoningDelta: nil, done: false)
        }

        do {
            let chunk = try JSONDecoder().decode(OpenAICompatibleChunk.self, from: data)
            guard let choice = chunk.choices.first else {
                return LineInfo(textDelta: nil, toolCallDeltas: [], reasoningDelta: nil, done: false)
            }

            let textDelta = (choice.delta.content?.isEmpty ?? true) ? nil : choice.delta.content
            let reasoningDelta = (choice.delta.reasoningContent?.isEmpty ?? true) ? nil : choice.delta.reasoningContent

            let tcDeltas = (choice.delta.toolCalls ?? []).map { tc in
                LineInfo.ToolCallDeltaInfo(
                    index: tc.index,
                    id: tc.id,
                    name: tc.function?.name,
                    argumentsDelta: tc.function?.arguments
                )
            }

            return LineInfo(
                textDelta: textDelta,
                toolCallDeltas: tcDeltas,
                reasoningDelta: reasoningDelta,
                done: choice.finishReason != nil
            )
        } catch {
            throw OpenAICompatibleError.decoding(message: error.localizedDescription)
        }
    }

    // MARK: - Request body

    /// Builds the request body as a dictionary so we can splice each tool's
    /// raw JSON Schema in as a proper JSON object (Codable can't embed
    /// arbitrary JSON without gymnastics).
    static func buildBody(
        model: String,
        messages: [ChatMessage],
        tools: [ToolSpec]
    ) throws -> Data {
        var dict: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": try messagesToDicts(messages)
        ]
        if !tools.isEmpty {
            dict["tools"] = try tools.map { spec -> [String: Any] in
                let parameters = try JSONSerialization.jsonObject(
                    with: Data(spec.inputSchemaJSON.utf8)
                )
                return [
                    "type": "function",
                    "function": [
                        "name": spec.name,
                        "description": spec.description,
                        "parameters": parameters
                    ] as [String: Any]
                ]
            }
        }
        return try JSONSerialization.data(withJSONObject: dict, options: [])
    }

    /// Converts our internal chat history to the OpenAI-compatible wire
    /// shape. Consecutive `.assistant` + `.toolCall` entries merge into a
    /// single assistant message with a `tool_calls` array; `.toolResult`
    /// entries become role="tool" messages with `tool_call_id`.
    static func messagesToDicts(_ messages: [ChatMessage]) throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var i = 0
        while i < messages.count {
            let msg = messages[i]
            switch msg.role {
            case .user, .system:
                out.append([
                    "role": msg.role.rawValue,
                    "content": msg.content
                ])
                i += 1

            case .assistant:
                var dict: [String: Any] = [
                    "role": "assistant",
                    "content": msg.content
                ]
                if let reasoning = msg.reasoningContent, !reasoning.isEmpty {
                    dict["reasoning_content"] = reasoning
                }
                var calls: [[String: Any]] = []
                var j = i + 1
                while j < messages.count, messages[j].role == .toolCall {
                    if let id = messages[j].toolCallID, let name = messages[j].toolName {
                        calls.append([
                            "id": id,
                            "type": "function",
                            "function": [
                                "name": name,
                                "arguments": messages[j].content
                            ] as [String: Any]
                        ])
                    }
                    j += 1
                }
                if !calls.isEmpty { dict["tool_calls"] = calls }
                out.append(dict)
                i = j

            case .toolCall:
                // Orphan tool call (no preceding assistant). Synthesise an
                // assistant message holding just the tool_calls array.
                var calls: [[String: Any]] = []
                var j = i
                while j < messages.count, messages[j].role == .toolCall {
                    if let id = messages[j].toolCallID, let name = messages[j].toolName {
                        calls.append([
                            "id": id,
                            "type": "function",
                            "function": [
                                "name": name,
                                "arguments": messages[j].content
                            ] as [String: Any]
                        ])
                    }
                    j += 1
                }
                out.append([
                    "role": "assistant",
                    "content": "",
                    "tool_calls": calls
                ])
                i = j

            case .toolResult:
                out.append([
                    "role": "tool",
                    "tool_call_id": msg.toolCallID ?? "",
                    "content": msg.content
                ])
                i += 1
            }
        }
        return out
    }
}
