import Foundation
@testable import TyKaoz

/// Test double for `EmbeddingProvider`. Uses a deterministic
/// bag-of-words projection: each unique word hashes into a dimension
/// and contributes 1.0 there, then the vector is L2-normalised.
///
/// Result: vectors of texts sharing vocabulary are close in cosine
/// space, texts with no overlap are roughly orthogonal. Enough
/// "semantics" for Finder tests to behave like the real embedder
/// would, without a network round-trip.
final class FakeEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    let id: String = "fake"
    let modelID: String = "fake-bow"
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
        return texts.map { Self.bagOfWordsVector($0, dimension: actualDimension) }
    }

    /// Pure function so tests can sanity-check directly.
    static func bagOfWordsVector(_ text: String, dimension: Int) -> [Float] {
        var v = [Float](repeating: 0, count: dimension)
        for word in tokenize(text) {
            // Stable per-word hash (Swift's hashValue is randomised
            // per launch; we need determinism across processes).
            var h: UInt64 = 1_469_598_103_934_665_603  // FNV-1a offset
            for byte in word.utf8 {
                h ^= UInt64(byte)
                h = h &* 1_099_511_628_211
            }
            let idx = Int(h % UInt64(dimension))
            v[idx] += 1.0
        }
        // L2-normalise so the magnitude doesn't dominate cosine.
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    /// Lowercase + split on anything that isn't a letter or digit.
    /// Drops accents not via NF anything fancy; we keep the raw bytes
    /// so "pagaie" and "PAGAIE" map to the same word.
    private static func tokenize(_ text: String) -> [Substring] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }
}
