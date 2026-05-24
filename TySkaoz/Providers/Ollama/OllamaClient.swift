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
}
