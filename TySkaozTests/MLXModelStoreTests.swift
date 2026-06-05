import Foundation
import Testing
@testable import TySkaoz

/// Smoke tests for MLXModelStore. Lightweight presence checks run in
/// the regular suite; the actual HuggingFace download is gated behind
/// `TYKAOZ_RUN_MLX_DOWNLOAD=1` because bge-m3-4bit is ~337 MB and
/// requires network — too heavy for routine `xcodebuild test` runs.
@MainActor
@Suite(.serialized)
struct MLXModelStoreTests {

    @Test
    func hubCacheRootMatchesSwiftHuggingFaceLayout() {
        let root = MLXModelStore.shared.hubCacheRoot()
        #expect(root != nil)
        let path = root?.path ?? ""
        // swift-huggingface points its sandboxed cache at
        // `URL.cachesDirectory/huggingface/hub` — we mirror it so
        // `localDirectory(modelID:)` finds the snapshot dir.
        #expect(path.hasSuffix("/Caches/huggingface/hub"))
    }

    @Test
    func notInstalledWhenNothingOnDisk() {
        let store = MLXModelStore.shared
        // Use a clearly-fake repo id so we never accidentally hit
        // a real download.
        #expect(!store.isInstalled(modelID: "fake-org/this-model-does-not-exist"))
        #expect(store.localDirectory(modelID: "fake-org/this-model-does-not-exist") == nil)
        #expect(store.sizeOnDisk(modelID: "fake-org/this-model-does-not-exist") == 0)
    }

    /// Heavy: actually downloads bge-m3-4bit (~337 MB). Gated.
    /// Verifies the round-trip: download → presence check → size > 0
    /// → cleanup.
    @Test
    func downloadsBgeM3IfRequested() async throws {
        guard ProcessInfo.processInfo.environment["TYKAOZ_RUN_MLX_DOWNLOAD"] == "1" else {
            print("Skipping MLX download test (set TYKAOZ_RUN_MLX_DOWNLOAD=1 to enable)")
            return
        }

        let store = MLXModelStore.shared
        let modelID = "mlx-community/bge-m3-mlx-4bit"

        // Ensure clean slate.
        store.remove(modelID: modelID)
        #expect(!store.isInstalled(modelID: modelID))

        var progressSeen = false
        _ = try await store.download(modelID: modelID) { progress in
            if progress > 0 { progressSeen = true }
        }
        #expect(progressSeen, "progress closure should fire at least once during a real download")
        #expect(store.isInstalled(modelID: modelID))
        let size = store.sizeOnDisk(modelID: modelID)
        #expect(size > 300 * 1024 * 1024, "bge-m3-4bit should weigh ~337 MB, got \(size) bytes")
    }
}
