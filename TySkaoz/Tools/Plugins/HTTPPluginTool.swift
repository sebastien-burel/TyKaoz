import Foundation

/// Bridges a plugin's tool definition to the `Tool` protocol. When invoked it
/// calls the configured HTTP endpoint — POST sends the arguments as the JSON
/// body, GET maps them to query items — and returns the response body as text.
struct HTTPPluginTool: Tool {
    let definition: PluginToolDef
    let session: URLSession

    init(definition: PluginToolDef, session: URLSession = .shared) {
        self.definition = definition
        self.session = session
    }

    private static let maxResponseChars = 100_000

    var spec: ToolSpec {
        ToolSpec(
            name: definition.name,
            description: definition.description,
            inputSchemaJSON: definition.inputSchemaJSON
        )
    }

    func execute(arguments: Data) async throws -> String {
        let request = try buildRequest(arguments: arguments)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw ToolError.execution(message: "erreur réseau : \(urlError.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw ToolError.execution(message: "réponse non-HTTP")
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(http.statusCode) else {
            let snippet = body.prefix(500)
            throw ToolError.execution(message: "HTTP \(http.statusCode)\(snippet.isEmpty ? "" : " : \(snippet)")")
        }

        return body.count > Self.maxResponseChars
            ? String(body.prefix(Self.maxResponseChars)) + "\n[tronqué]"
            : body
    }

    private func buildRequest(arguments: Data) throws -> URLRequest {
        switch definition.method {
        case .post:
            var request = URLRequest(url: definition.url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = arguments.isEmpty ? Data("{}".utf8) : arguments
            applyHeaders(&request)
            request.timeoutInterval = 30
            return request

        case .get:
            guard var components = URLComponents(url: definition.url, resolvingAgainstBaseURL: false) else {
                throw ToolError.execution(message: "URL invalide")
            }
            if let dict = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] {
                let items = dict
                    .sorted { $0.key < $1.key }
                    .map { URLQueryItem(name: $0.key, value: Self.stringify($0.value)) }
                if !items.isEmpty {
                    components.queryItems = (components.queryItems ?? []) + items
                }
            }
            guard let url = components.url else {
                throw ToolError.execution(message: "construction d'URL impossible")
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyHeaders(&request)
            request.timeoutInterval = 30
            return request
        }
    }

    private func applyHeaders(_ request: inout URLRequest) {
        for (key, value) in definition.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private static func stringify(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let b = value as? Bool { return b ? "true" : "false" }
        return String(describing: value)
    }
}
