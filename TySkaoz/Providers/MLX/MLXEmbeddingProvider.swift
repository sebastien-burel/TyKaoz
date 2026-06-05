import Foundation

/// `EmbeddingProvider` running bge-m3 (and friends) in-process on
/// Apple Silicon via MLX-Swift. Phase A1: skeleton that conforms to
/// the protocol and returns zero vectors — wires the UI/settings
/// plumbing end-to-end before A3 plugs the real MLX runtime in.
///
/// Lifecycle: the provider is cheap (no model touched at init); the
/// heavy work (model load, tokenizer parse, Metal command-queue
/// warmup) lives in `MLXEmbeddingActor`, added in commit A3.
struct MLXEmbeddingProvider: EmbeddingProvider {
    let id: String = "mlx"
    let modelID: String
    let dimension: Int

    init(modelID: String, dimension: Int) {
        self.modelID = modelID
        self.dimension = dimension
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        // A1 placeholder: return zero vectors so the indexer flow
        // doesn't crash while the picker / settings / WikiManager
        // wiring is validated. Commit A3 swaps this for a real
        // forward pass through MLX-Swift.
        return texts.map { _ in
            [Float](repeating: 0, count: dimension)
        }
    }
}
