import Foundation
import MLXEmbedders
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Knows where MLX models live on disk and triggers HuggingFace
/// downloads via `swift-huggingface`'s `HubClient`. Sandboxed apps get
/// the hub cache redirected automatically; we surface the on-disk
/// path for the UI to show in the model-management pane (Phase B).
///
/// Phase A2: download + presence check only. The actual embedding
/// pipeline (model load into Metal, mean pooling, forward pass)
/// lands in commit A3 inside `MLXEmbeddingActor`.
@MainActor
final class MLXModelStore {
    /// Singleton — there's only ever one HF cache directory per app
    /// instance, so a global makes sense.
    static let shared = MLXModelStore()

    enum Failure: LocalizedError {
        case insufficientDiskSpace(needed: Int64, available: Int64)
        case downloadFailed(modelID: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .insufficientDiskSpace(let needed, let available):
                let need = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
                let have = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
                return "Pas assez d'espace disque (besoin : \(need), dispo : \(have))."
            case .downloadFailed(let modelID, let err):
                return """
                Échec du téléchargement de « \(modelID) » : \
                \(err.localizedDescription). Vérifie que le slug est \
                un repo HuggingFace valide (ex : \
                `mlx-community/bge-m3-mlx-4bit`).
                """
            }
        }
    }

    /// Rough sizes (bytes) used by the pre-flight check before
    /// kicking off a download. Numbers are approximate — HF reshards
    /// safetensors occasionally and the actual on-disk size drifts.
    private static let knownSizes: [String: Int64] = [
        "mlx-community/bge-m3-mlx-4bit": 337 * 1024 * 1024,
        "mlx-community/bge-small-en-v1.5-4bit": 35 * 1024 * 1024,
        "mlx-community/nomic-embed-text-v1.5-4bit": 90 * 1024 * 1024,
    ]

    /// Macro-produced `Downloader` wrapping `HubClient`. Stored once
    /// so the type — opaque from the macro expansion — doesn't leak
    /// into property declarations.
    private let downloader: any Downloader
    private let tokenizerLoader: any TokenizerLoader

    private init() {
        // Default hub stores under `~/.cache/huggingface/hub/`, which
        // becomes `~/Library/Containers/<bundle id>/Data/.cache/...`
        // under the sandbox. Good for now — Phase B will let the
        // user pick a custom location.
        self.downloader = #hubDownloader()
        self.tokenizerLoader = #huggingFaceTokenizerLoader()
    }

    // MARK: - Presence

    /// Tries to resolve a model's local directory by parsing the HF
    /// cache layout. Returns `nil` when nothing is on disk.
    func localDirectory(modelID: String) -> URL? {
        guard let cacheRoot = hubCacheRoot() else { return nil }
        // HF Hub stores repos as `models--<org>--<name>/snapshots/<rev>/`.
        let slug = "models--" + modelID.replacingOccurrences(of: "/", with: "--")
        let repoRoot = cacheRoot.appendingPathComponent(slug, isDirectory: true)
        let snapshots = repoRoot.appendingPathComponent("snapshots", isDirectory: true)
        guard let revisions = try? FileManager.default.contentsOfDirectory(
            at: snapshots,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ), let firstRevision = revisions.first else {
            return nil
        }
        return firstRevision
    }

    /// `true` when the model directory is on disk and its total size
    /// is at least 90% of the expected size — accounts for minor
    /// variation across revisions while still catching a
    /// half-downloaded snapshot.
    func isInstalled(modelID: String) -> Bool {
        guard let dir = localDirectory(modelID: modelID) else { return false }
        let actual = (try? diskSize(of: dir)) ?? 0
        let expected = Self.knownSizes[modelID] ?? 0
        if expected == 0 { return actual > 0 }
        return actual >= Int64(Double(expected) * 0.9)
    }

    /// Bytes on disk for a specific model. Useful for the cache
    /// management UI.
    func sizeOnDisk(modelID: String) -> Int64 {
        guard let dir = localDirectory(modelID: modelID) else { return 0 }
        return (try? diskSize(of: dir)) ?? 0
    }

    // MARK: - Download

    /// Downloads a model from HuggingFace, reporting progress (0…1)
    /// via the closure. Idempotent: if the model is already on disk,
    /// returns the cached path immediately with progress = 1.
    ///
    /// Throws on disk-space shortage or network failure.
    @discardableResult
    func download(
        modelID: String,
        progressHandler: @MainActor @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        if isInstalled(modelID: modelID),
           let dir = localDirectory(modelID: modelID) {
            progressHandler(1.0)
            return dir
        }

        try preflightDiskSpace(for: modelID)

        // Drive the download through EmbedderModelFactory — same
        // code path the embed actor (A3) will use later. We don't
        // need the resulting container yet, just the side-effect of
        // files landing in the hub cache.
        do {
            _ = try await EmbedderModelFactory.shared.loadContainer(
                from: downloader,
                using: tokenizerLoader,
                configuration: ModelConfiguration(id: modelID)
            ) { @Sendable progress in
                Task { @MainActor in
                    progressHandler(progress.fractionCompleted)
                }
            }
        } catch {
            throw Failure.downloadFailed(modelID: modelID, underlying: error)
        }

        guard let dir = localDirectory(modelID: modelID) else {
            throw Failure.downloadFailed(
                modelID: modelID,
                underlying: NSError(
                    domain: "MLXModelStore",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Modèle introuvable après téléchargement."]
                )
            )
        }
        return dir
    }

    // MARK: - Cache management

    /// Best-effort: removes the model's snapshot + blob directories.
    func remove(modelID: String) {
        guard let cacheRoot = hubCacheRoot() else { return }
        let slug = "models--" + modelID.replacingOccurrences(of: "/", with: "--")
        let repoRoot = cacheRoot.appendingPathComponent(slug, isDirectory: true)
        try? FileManager.default.removeItem(at: repoRoot)
    }

    /// Total bytes occupied on disk by the whole HF cache.
    func totalCacheSize() -> Int64 {
        guard let cacheRoot = hubCacheRoot() else { return 0 }
        return (try? diskSize(of: cacheRoot)) ?? 0
    }

    /// Root of the HF Hub cache for UI display. Under sandbox this
    /// resolves to `~/Library/Containers/<bundle id>/Data/.cache/
    /// huggingface/hub/`.
    func hubCacheRoot() -> URL? {
        // HuggingFace.HubClient writes to `<HOME>/.cache/huggingface/
        // hub/` — derive the path from NSHomeDirectory so it stays
        // correct under the sandbox redirect.
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return home
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("hub", isDirectory: true)
    }

    // MARK: - Helpers

    private func preflightDiskSpace(for modelID: String) throws {
        let needed = (Self.knownSizes[modelID] ?? 500 * 1024 * 1024) * 2
        let available = freeDiskBytes()
        if available < needed {
            throw Failure.insufficientDiskSpace(needed: needed, available: available)
        }
    }

    private func freeDiskBytes() -> Int64 {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ) else { return 0 }
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private nonisolated func diskSize(of url: URL) throws -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]
            )
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}
