import Foundation

enum MistralClientError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case network(message: String)
    case http(status: Int)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:        return "Clé API Mistral manquante."
        case .network(let msg):     return "Erreur réseau : \(msg)"
        case .http(let status):     return "Réponse HTTP \(status)."
        case .decoding(let msg):    return "Réponse inattendue : \(msg)"
        }
    }
}

struct MistralClient {
    let apiKey: String
    let session: URLSession
    let baseURL: URL

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.mistral.ai/v1")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - List models

    func listModels() async throws -> [MistralModelsResponse.Model] {
        var request = URLRequest(url: baseURL.appending(path: "/models"))
        request.timeoutInterval = 10
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw MistralClientError.network(message: urlError.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MistralClientError.network(message: "réponse non-HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MistralClientError.http(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(MistralModelsResponse.self, from: data).data
        } catch {
            throw MistralClientError.decoding(message: error.localizedDescription)
        }
    }

    // MARK: - Chat (streaming)

    func chat(model: String, messages: [MistralChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appending(path: "/chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.timeoutInterval = 60
                    request.httpBody = try JSONEncoder().encode(
                        MistralChatRequest(model: model, messages: messages, stream: true)
                    )

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await session.bytes(for: request)
                    } catch let urlError as URLError {
                        throw MistralClientError.network(message: urlError.localizedDescription)
                    }

                    guard let http = response as? HTTPURLResponse else {
                        throw MistralClientError.network(message: "réponse non-HTTP")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw MistralClientError.http(status: http.statusCode)
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

    /// Parses one SSE line. Returns the content delta (nil if not a payload
    /// or empty content) and a `done` flag (true on `[DONE]` or
    /// `finish_reason != nil`). Blank lines and non-`data:` lines are no-ops.
    static func parseLine(_ raw: Data) throws -> (delta: String?, done: Bool) {
        guard let line = String(data: raw, encoding: .utf8) else { return (nil, false) }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, false) }
        guard trimmed.hasPrefix("data:") else { return (nil, false) } // ignore "event:", "id:" etc.

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return (nil, true) }

        guard let data = payload.data(using: .utf8) else { return (nil, false) }
        do {
            let chunk = try JSONDecoder().decode(MistralChatChunk.self, from: data)
            let content = chunk.choices.first?.delta.content
            let finished = chunk.choices.first?.finishReason != nil
            let delta = (content?.isEmpty ?? true) ? nil : content
            return (delta, finished)
        } catch {
            throw MistralClientError.decoding(message: error.localizedDescription)
        }
    }
}
