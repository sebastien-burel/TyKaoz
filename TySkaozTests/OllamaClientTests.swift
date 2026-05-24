import Foundation
import Testing
@testable import TySkaoz

@Suite(.serialized)
struct OllamaClientTests {
    private let baseURL = URL(string: "http://localhost:11434")!

    @Test
    func decodesTagsResponse() async throws {
        let json = """
        {
          "models": [
            {
              "name": "llama3.2:latest",
              "model": "llama3.2:latest",
              "modified_at": "2026-05-01T12:34:56.789Z",
              "size": 2019393189,
              "digest": "sha256:abc"
            },
            {
              "name": "qwen2.5:7b",
              "model": "qwen2.5:7b",
              "modified_at": "2026-04-15T10:00:00Z",
              "size": 4500000000,
              "digest": "sha256:def"
            }
          ]
        }
        """.data(using: .utf8)!

        let session = MockURLProtocol.session(data: json, status: 200)
        let client = OllamaClient(baseURL: baseURL, session: session)

        let models = try await client.listModels()

        #expect(models.count == 2)
        #expect(models[0].name == "llama3.2:latest")
        #expect(models[0].size == 2019393189)
        #expect(models[1].name == "qwen2.5:7b")
    }

    @Test
    func throwsHTTPErrorOnNon2xx() async {
        let session = MockURLProtocol.session(data: Data(), status: 500)
        let client = OllamaClient(baseURL: baseURL, session: session)

        await #expect(throws: OllamaClientError.http(status: 500)) {
            try await client.listModels()
        }
    }

    @Test
    func throwsDecodingErrorOnGarbage() async {
        let session = MockURLProtocol.session(data: Data("not json".utf8), status: 200)
        let client = OllamaClient(baseURL: baseURL, session: session)

        await #expect(throws: OllamaClientError.self) {
            try await client.listModels()
        }
    }

    @Test
    func throwsNetworkErrorOnTransportFailure() async {
        let session = MockURLProtocol.session(error: URLError(.cannotConnectToHost))
        let client = OllamaClient(baseURL: baseURL, session: session)

        await #expect(throws: OllamaClientError.self) {
            try await client.listModels()
        }
    }
}
