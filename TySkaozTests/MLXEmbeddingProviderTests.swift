import Foundation
import Testing
@testable import TySkaoz

/// Tests for the MLX embedding pipeline. The cheap conformance tests
/// run in every suite; the real semantic check is gated behind
/// `TYKAOZ_RUN_MLX_DOWNLOAD=1` because it requires downloading
/// bge-m3-4bit (~337 MB) on first run and ~5 s of inference.
@MainActor
@Suite(.serialized)
struct MLXEmbeddingProviderTests {

    private static let modelID = "mlx-community/bge-m3-mlx-4bit"
    private static let dimension = 1024

    @Test
    func emptyInputReturnsEmpty() async throws {
        let provider = MLXEmbeddingProvider(modelID: Self.modelID, dimension: Self.dimension)
        let vectors = try await provider.embed([])
        #expect(vectors.isEmpty)
    }

    /// Heavy: downloads (if missing) + loads bge-m3-4bit, runs three
    /// forward passes, asserts a semantic ordering. Gated.
    @Test
    func cosineCatKittenBeatsCatCar() async throws {
        guard ProcessInfo.processInfo.environment["TYKAOZ_RUN_MLX_DOWNLOAD"] == "1" else {
            print("Skipping MLX embedding semantic test (set TYKAOZ_RUN_MLX_DOWNLOAD=1 to enable)")
            return
        }

        let provider = MLXEmbeddingProvider(modelID: Self.modelID, dimension: Self.dimension)
        let vectors = try await provider.embed(["cat", "kitten", "car"])
        #expect(vectors.count == 3)
        #expect(vectors[0].count == Self.dimension)

        let catKitten = cosine(vectors[0], vectors[1])
        let catCar    = cosine(vectors[0], vectors[2])

        #expect(catKitten > catCar,
                "cat/kitten (\(catKitten)) should be more similar than cat/car (\(catCar))")
        // Sanity: both are positive (the vectors are normalised so
        // dot product == cosine; should be in [0, 1] for vaguely
        // related concepts).
        #expect(catKitten > 0.3)
    }

    @Test
    func dimensionMatchesBgeM3() async throws {
        guard ProcessInfo.processInfo.environment["TYKAOZ_RUN_MLX_DOWNLOAD"] == "1" else {
            print("Skipping MLX dimension test (set TYKAOZ_RUN_MLX_DOWNLOAD=1 to enable)")
            return
        }
        let provider = MLXEmbeddingProvider(modelID: Self.modelID, dimension: Self.dimension)
        let vectors = try await provider.embed(["Bonjour le monde"])
        #expect(vectors.count == 1)
        #expect(vectors[0].count == Self.dimension)
    }

    // MARK: - Helpers

    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        // Vectors come back L2-normalised from the actor, so the
        // dot product is the cosine — but we don't assume that here
        // (defensive).
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<min(a.count, b.count) {
            dot += a[i] * b[i]
            na  += a[i] * a[i]
            nb  += b[i] * b[i]
        }
        return dot / (sqrt(na) * sqrt(nb) + 1e-9)
    }
}
