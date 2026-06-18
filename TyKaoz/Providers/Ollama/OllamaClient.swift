import Foundation

enum OllamaClientError: Error, LocalizedError, Equatable {
    case invalidURL
    case network(message: String)
    case http(status: Int, body: String? = nil)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL invalide."
        case .network(let message):
            return "Erreur réseau : \(message)"
        case .http(let status, let body):
            if let body, !body.isEmpty {
                return "Réponse HTTP \(status) : \(body)"
            }
            return "Réponse HTTP \(status)."
        case .decoding(let message):
            return "Réponse inattendue : \(message)"
        }
    }
}

struct OllamaClient {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func listModels() async throws -> [OllamaModel] {
        let url = baseURL.appending(path: "/api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw OllamaClientError.network(message: urlError.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OllamaClientError.network(message: "réponse non-HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OllamaClientError.http(status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(OllamaTagsResponse.self, from: data).models
        } catch {
            throw OllamaClientError.decoding(message: error.localizedDescription)
        }
    }

    // MARK: - Embeddings

    /// Batched call to `/api/embed`. The newer endpoint takes
    /// `input: [String]` and returns `embeddings: [[Float]]` in the same
    /// order — the indexer hits this once per page (one batch per chunk
    /// set) so latency amortises across chunks of a single document.
    func embed(model: String, inputs: [String]) async throws -> [[Float]] {
        guard !inputs.isEmpty else { return [] }

        let url = baseURL.appending(path: "/api/embed")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = ["model": model, "input": inputs]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw OllamaClientError.network(message: urlError.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OllamaClientError.network(message: "réponse non-HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            let trimmed = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw OllamaClientError.http(
                status: http.statusCode,
                body: (trimmed?.isEmpty == false) ? trimmed : nil
            )
        }

        struct EmbedResponse: Decodable {
            let embeddings: [[Float]]
        }
        do {
            return try JSONDecoder().decode(EmbedResponse.self, from: data).embeddings
        } catch {
            throw OllamaClientError.decoding(message: error.localizedDescription)
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
                    let url = baseURL.appending(path: "/api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60
                    request.httpBody = try Self.buildBody(model: model, messages: messages, tools: tools)

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await session.bytes(for: request)
                    } catch let urlError as URLError {
                        throw OllamaClientError.network(message: urlError.localizedDescription)
                    }

                    guard let http = response as? HTTPURLResponse else {
                        throw OllamaClientError.network(message: "réponse non-HTTP")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var raw = Data()
                        for try await byte in bytes {
                            raw.append(byte)
                            if raw.count > 1500 { break }
                        }
                        // Decode as UTF-8 — Ollama error bodies are UTF-8
                        // JSON; a byte-wise decode mangles accents and the
                        // model content echoed back in tool-parse errors.
                        let body = String(decoding: raw, as: UTF8.self)
                        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                        throw OllamaClientError.http(
                            status: http.statusCode,
                            body: trimmed.isEmpty ? nil : trimmed
                        )
                    }

                    var buffer = Data()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A {
                            let info = try Self.parseChunk(line: buffer)
                            buffer.removeAll(keepingCapacity: true)
                            if let delta = info.textDelta {
                                continuation.yield(.textDelta(delta))
                            }
                            for tc in info.toolCalls {
                                continuation.yield(.toolCall(
                                    id: tc.id,
                                    name: tc.name,
                                    argumentsJSON: tc.argumentsJSON
                                ))
                            }
                            if info.done {
                                continuation.finish()
                                return
                            }
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty {
                        let info = try Self.parseChunk(line: buffer)
                        if let delta = info.textDelta {
                            continuation.yield(.textDelta(delta))
                        }
                        for tc in info.toolCalls {
                            continuation.yield(.toolCall(
                                id: tc.id,
                                name: tc.name,
                                argumentsJSON: tc.argumentsJSON
                            ))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Chunk parsing

    struct ChunkInfo: Equatable {
        let textDelta: String?
        let toolCalls: [ToolCallInfo]
        let done: Bool

        struct ToolCallInfo: Equatable {
            let id: String
            let name: String
            let argumentsJSON: String
        }
    }

    /// Parses one NDJSON line. Ollama doesn't assign tool-call IDs, so we
    /// synthesise one (UUID) per call — uniqueness within a conversation is
    /// all our orchestration loop needs.
    static func parseChunk(line: Data) throws -> ChunkInfo {
        let trimmed = line.trimmingPrefixAndSuffix(in: [0x20, 0x09, 0x0D])
        guard !trimmed.isEmpty else {
            return ChunkInfo(textDelta: nil, toolCalls: [], done: false)
        }
        do {
            let chunk = try JSONDecoder().decode(OllamaChatChunk.self, from: trimmed)
            let textDelta = chunk.message.content.isEmpty ? nil : chunk.message.content
            let toolCalls = (chunk.message.toolCalls ?? []).map { tc in
                ChunkInfo.ToolCallInfo(
                    id: UUID().uuidString,
                    name: tc.function.name,
                    argumentsJSON: tc.function.arguments.jsonString
                )
            }
            return ChunkInfo(
                textDelta: textDelta,
                toolCalls: toolCalls,
                done: chunk.done
            )
        } catch {
            throw OllamaClientError.decoding(message: error.localizedDescription)
        }
    }

    // MARK: - Request body

    /// Builds the request body as a dictionary so each tool's JSON Schema
    /// and each tool-call's arguments embed as proper JSON objects.
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

    /// Converts our flat ChatMessage history into Ollama's wire format.
    /// The shape mirrors OpenAI's (assistant with optional tool_calls,
    /// role="tool" for results) but Ollama expects `arguments` as a JSON
    /// object, not a string — we parse before splicing in.
    static func messagesToDicts(_ messages: [ChatMessage]) throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var i = 0
        while i < messages.count {
            let msg = messages[i]
            switch msg.role {
            case .system, .user:
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
                var calls: [[String: Any]] = []
                var j = i + 1
                while j < messages.count, messages[j].role == .toolCall {
                    if let name = messages[j].toolName {
                        let args = parseToolArgs(messages[j].content)
                        calls.append([
                            "function": [
                                "name": name,
                                "arguments": args
                            ] as [String: Any]
                        ])
                    }
                    j += 1
                }
                if !calls.isEmpty { dict["tool_calls"] = calls }
                out.append(dict)
                i = j

            case .toolCall:
                var calls: [[String: Any]] = []
                var j = i
                while j < messages.count, messages[j].role == .toolCall {
                    if let name = messages[j].toolName {
                        let args = parseToolArgs(messages[j].content)
                        calls.append([
                            "function": [
                                "name": name,
                                "arguments": args
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
                    "content": msg.content
                ])
                i += 1
            }
        }
        return out
    }

    private static func parseToolArgs(_ json: String) -> Any {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return [String: Any]()
        }
        return parsed
    }
}

private extension Data {
    func trimmingPrefixAndSuffix(in bytes: Set<UInt8>) -> Data {
        var start = startIndex
        var end = endIndex
        while start < end, bytes.contains(self[start]) { start = index(after: start) }
        while end > start, bytes.contains(self[index(before: end)]) { end = index(before: end) }
        return subdata(in: start..<end)
    }
}
