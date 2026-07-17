import Foundation
import TyKaozKit

/// `EmbeddingProvider` running bge-m3 (and friends) in-process on
/// Apple Silicon via MLX-Swift. Phase A3: delegates to
/// `MLXEmbeddingActor` which holds the loaded container and
/// serializes forward passes (MLX = single Metal command queue).
///
/// The provider itself is cheap and stateless — all heavy lifting
/// (download + load + inference) lives in the actor.
struct MLXEmbeddingProvider: EmbeddingProvider {
    let id: String = "mlx"
    let modelID: String
    let dimension: Int

    init(modelID: String, dimension: Int) {
        self.modelID = modelID
        self.dimension = dimension
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        let actor = await MLXEmbeddingActor.shared(for: modelID)
        return try await actor.embed(texts)
    }
}
