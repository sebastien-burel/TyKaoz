import Foundation

enum AnthropicClientError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case network(message: String)
    case http(status: Int)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:        return "Clé API Anthropic manquante."
        case .network(let msg):     return "Erreur réseau : \(msg)"
        case .http(let status):     return "Réponse HTTP \(status)."
        case .decoding(let msg):    return "Réponse inattendue : \(msg)"
        }
    }
}

struct AnthropicClient {
    let apiKey: String
    let session: URLSession
    let baseURL: URL
    let anthropicVersion: String

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        anthropicVersion: String = "2023-06-01",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.anthropicVersion = anthropicVersion
        self.session = session
    }

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
    }

    // MARK: - List models

    func listModels() async throws -> [AnthropicModelsResponse.Model] {
        var request = URLRequest(url: baseURL.appending(path: "/models"))
        request.timeoutInterval = 10
        authorize(&request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw AnthropicClientError.network(message: urlError.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicClientError.network(message: "réponse non-HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AnthropicClientError.http(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(AnthropicModelsResponse.self, from: data).data
        } catch {
            throw AnthropicClientError.decoding(message: error.localizedDescription)
        }
    }

    // MARK: - Chat (streaming)

    func chat(
        model: String,
        system: String?,
        messages: [AnthropicMessage],
        maxTokens: Int = 4096
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appending(path: "/messages"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    authorize(&request)
                    request.timeoutInterval = 60
                    request.httpBody = try JSONEncoder().encode(
                        AnthropicChatRequest(
                            model: model,
                            messages: messages,
                            system: system,
                            stream: true,
                            maxTokens: maxTokens
                        )
                    )

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await session.bytes(for: request)
                    } catch let urlError as URLError {
                        throw AnthropicClientError.network(message: urlError.localizedDescription)
                    }

                    guard let http = response as? HTTPURLResponse else {
                        throw AnthropicClientError.network(message: "réponse non-HTTP")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw AnthropicClientError.http(status: http.statusCode)
                    }

                    var buffer = Data()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A {
                            let (delta, done) = try Self.parseLine(buffer)
                            buffer.removeAll(keepingCapacity: true)
                            if let delta { continuation.yield(delta) }
                            if done { continuation.finish(); return }
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty {
                        let (delta, _) = try Self.parseLine(buffer)
                        if let delta { continuation.yield(delta) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Parses one SSE line. Anthropic emits both `event:` and `data:` lines;
    /// the `data:` payload self-describes via its `type` field so we can
    /// ignore the `event:` preamble.
    /// - Returns `delta` for `content_block_delta` with `text_delta`.
    /// - Returns `done=true` for `message_stop`.
    /// - Other types (message_start, content_block_start, ping, …) are no-ops.
    static func parseLine(_ raw: Data) throws -> (delta: String?, done: Bool) {
        guard let line = String(data: raw, encoding: .utf8) else { return (nil, false) }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, false) }
        guard trimmed.hasPrefix("data:") else { return (nil, false) }

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return (nil, false) }

        do {
            let event = try JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
            switch event.type {
            case "content_block_delta":
                if event.delta?.type == "text_delta", let text = event.delta?.text, !text.isEmpty {
                    return (text, false)
                }
                return (nil, false)
            case "message_stop":
                return (nil, true)
            default:
                return (nil, false)
            }
        } catch {
            throw AnthropicClientError.decoding(message: error.localizedDescription)
        }
    }
}
