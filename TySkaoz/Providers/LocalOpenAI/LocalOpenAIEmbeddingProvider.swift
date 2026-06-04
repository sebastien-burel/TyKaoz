import Foundation

/// `EmbeddingProvider` conformer for self-hosted OpenAI-compatible
/// servers (vLLM, LM Studio, llama.cpp). Hits `/v1/embeddings` and
/// returns the vectors in input order. Pinned model + dimension at
/// construction so the indexer can guard against schema mismatches.
struct LocalOpenAIEmbeddingProvider: EmbeddingProvider {
    let id: String = "localOpenAI"
    let baseURL: URL
    let modelID: String
    let dimension: Int

    private let client: OpenAICompatibleClient

    init(baseURL: URL, apiKey: String, modelID: String, dimension: Int, session: URLSession = .shared) {
        // Same /v1 normalisation as the chat provider so users only
        // configure one URL across the app.
        let normalized = LocalOpenAIProvider.normalize(baseURL)
        self.baseURL = normalized
        self.modelID = modelID
        self.dimension = dimension
        self.client = OpenAICompatibleClient(baseURL: normalized, apiKey: apiKey, session: session)
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        try await client.embed(model: modelID, inputs: texts)
    }
}
