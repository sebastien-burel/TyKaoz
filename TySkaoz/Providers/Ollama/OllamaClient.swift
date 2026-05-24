import Foundation

enum OllamaClientError: Error, LocalizedError, Equatable {
    case invalidURL
    case network(message: String)
    case http(status: Int)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL invalide."
        case .network(let message):
            return "Erreur réseau : \(message)"
        case .http(let status):
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

    func chat(model: String, messages: [OllamaChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = baseURL.appending(path: "/api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60
                    request.httpBody = try JSONEncoder().encode(
                        OllamaChatRequest(model: model, messages: messages, stream: true)
                    )

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
                        throw OllamaClientError.http(status: http.statusCode)
                    }

                    var buffer = Data()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A { // newline
                            let (delta, done) = try Self.parseChunk(line: buffer)
                            buffer.removeAll(keepingCapacity: true)
                            if let delta { continuation.yield(delta) }
                            if done { continuation.finish(); return }
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty {
                        let (delta, _) = try Self.parseChunk(line: buffer)
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

    /// Parses one NDJSON line. Returns the content delta (nil if empty) and the
    /// done flag. Empty/whitespace lines yield (nil, false).
    static func parseChunk(line: Data) throws -> (delta: String?, done: Bool) {
        let trimmed = line.trimmingPrefixAndSuffix(in: [0x20, 0x09, 0x0D])
        guard !trimmed.isEmpty else { return (nil, false) }
        do {
            let chunk = try JSONDecoder().decode(OllamaChatChunk.self, from: trimmed)
            return (chunk.message.content.isEmpty ? nil : chunk.message.content, chunk.done)
        } catch {
            throw OllamaClientError.decoding(message: error.localizedDescription)
        }
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
