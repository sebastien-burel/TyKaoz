import Foundation

enum GoogleClientError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case network(message: String)
    case http(status: Int)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:        return "Clé API Google manquante."
        case .network(let msg):     return "Erreur réseau : \(msg)"
        case .http(let status):     return "Réponse HTTP \(status)."
        case .decoding(let msg):    return "Réponse inattendue : \(msg)"
        }
    }
}

struct GoogleClient {
    let apiKey: String
    let session: URLSession
    let baseURL: URL

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - List models

    func listModels() async throws -> [GoogleModelsResponse.Model] {
        var request = URLRequest(url: baseURL.appending(path: "/models"))
        request.timeoutInterval = 10
        request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-goog-api-key")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw GoogleClientError.network(message: urlError.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GoogleClientError.network(message: "réponse non-HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleClientError.http(status: http.statusCode)
        }
        do {
            let decoded = try JSONDecoder().decode(GoogleModelsResponse.self, from: data)
            // Only keep models that advertise generateContent support — the
            // catalog also includes embedding and image models we'd reject in
            // any case.
            return decoded.models.filter {
                $0.supportedGenerationMethods?.contains("generateContent") ?? true
            }
        } catch {
            throw GoogleClientError.decoding(message: error.localizedDescription)
        }
    }

    // MARK: - Chat (streaming)

    func chat(
        model: String,
        system: String?,
        contents: [GoogleContent]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let path = "/models/\(model):streamGenerateContent"
                    var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
                    components.queryItems = [URLQueryItem(name: "alt", value: "sse")]

                    var request = URLRequest(url: components.url!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-goog-api-key")
                    request.timeoutInterval = 60

                    let systemInstruction: GoogleContent? = system.flatMap {
                        $0.isEmpty ? nil : GoogleContent(role: nil, parts: [GooglePart(text: $0)])
                    }
                    request.httpBody = try JSONEncoder().encode(
                        GoogleChatRequest(contents: contents, systemInstruction: systemInstruction)
                    )

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await session.bytes(for: request)
                    } catch let urlError as URLError {
                        throw GoogleClientError.network(message: urlError.localizedDescription)
                    }

                    guard let http = response as? HTTPURLResponse else {
                        throw GoogleClientError.network(message: "réponse non-HTTP")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw GoogleClientError.http(status: http.statusCode)
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

    /// Parses one SSE line from `?alt=sse`. Each data payload contains a
    /// `candidates[0].content.parts[*].text` to concatenate, plus an optional
    /// `finishReason` ("STOP", "MAX_TOKENS", "SAFETY", …) on the last chunk.
    static func parseLine(_ raw: Data) throws -> (delta: String?, done: Bool) {
        guard let line = String(data: raw, encoding: .utf8) else { return (nil, false) }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, false) }
        guard trimmed.hasPrefix("data:") else { return (nil, false) }

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return (nil, false) }

        do {
            let chunk = try JSONDecoder().decode(GoogleStreamChunk.self, from: data)
            guard let candidate = chunk.candidates?.first else { return (nil, false) }
            let texts = candidate.content?.parts?.compactMap { $0.text } ?? []
            let text = texts.joined()
            let done = candidate.finishReason != nil
            let delta = text.isEmpty ? nil : text
            return (delta, done)
        } catch {
            throw GoogleClientError.decoding(message: error.localizedDescription)
        }
    }
}
