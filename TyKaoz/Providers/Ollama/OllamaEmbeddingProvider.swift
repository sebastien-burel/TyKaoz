import Foundation

/// First conformer of `EmbeddingProvider`. Wraps `OllamaClient.embed` and
/// pins the model + dimension at construction time so the caller (Indexer)
/// can compare against `WikiSchemaV1.embeddingDimension` before writing.
struct OllamaEmbeddingProvider: EmbeddingProvider {
    let id: String = "ollama"
    let baseURL: URL
    let modelID: String
    let dimension: Int

    private let client: OllamaClient

    init(baseURL: URL, modelID: String, dimension: Int, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.modelID = modelID
        self.dimension = dimension
        self.client = OllamaClient(baseURL: baseURL, session: session)
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        try await client.embed(model: modelID, inputs: texts)
    }
}
