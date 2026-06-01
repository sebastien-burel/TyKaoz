import Foundation
@testable import TySkaoz

/// Test double for `EmbeddingProvider`. Returns deterministic vectors
/// derived from each input string's hash so tests can compare expected
/// vs returned without coupling to a real model.
final class FakeEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    let id: String = "fake"
    let modelID: String = "fake-model"
    let dimension: Int

    /// Lets tests force a mismatch between declared dim and actually
    /// returned vectors, to exercise the indexer's dimension guard.
    private let actualDimension: Int

    private(set) var callCount: Int = 0

    init(dimension: Int, actualDimension: Int? = nil) {
        self.dimension = dimension
        self.actualDimension = actualDimension ?? dimension
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        callCount += 1
        return texts.map { text in
            var rng = UInt32(truncatingIfNeeded: text.hashValue)
            return (0..<actualDimension).map { _ in
                rng = rng &* 1_664_525 &+ 1_013_904_223
                return Float(rng & 0xFFFF) / Float(0xFFFF)
            }
        }
    }
}
