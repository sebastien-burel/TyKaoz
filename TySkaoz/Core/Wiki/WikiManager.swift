import Foundation
import Observation

/// Lifecycle owner for the wiki feature. Bridges `AppSettings` to a
/// `WikiContext` + `WikiFileWatcher` and surfaces a ready/idle state
/// for the UI. Constructed once at app launch and lives for the
/// process lifetime.
@Observable @MainActor
final class WikiManager {
    enum State {
        case disabled
        case ready(WikiContext)
        case failed(message: String)

        var context: WikiContext? {
            if case .ready(let ctx) = self { return ctx } else { return nil }
        }
    }

    private(set) var state: State = .disabled
    @ObservationIgnored private var watcher: WikiFileWatcher?

    /// Default store location inside the sandbox container — works
    /// without any entitlement. Phase 7+ can layer an override via
    /// security-scoped bookmark for Obsidian interop.
    static func defaultStoreRoot() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        return appSupport.appendingPathComponent("wiki-store", isDirectory: true)
    }

    /// Builds (or rebuilds) the context based on the current settings.
    /// Idempotent: if the manager is already ready with the same
    /// configuration, this is a no-op.
    func reconcile(settings: AppSettings, ollamaBaseURL: URL?) {
        guard settings.wikiEnabled else {
            tearDown()
            state = .disabled
            return
        }

        // Already running? Embedder + dim must still match the live
        // schema — if the user flipped them, we'd need a rebuild
        // migration. For MVP, refuse silently and surface in the UI.
        if case .ready = state { return }

        do {
            let storeRoot = Self.defaultStoreRoot()
            try FileManager.default.createDirectory(
                at: storeRoot, withIntermediateDirectories: true
            )
            let pool = try WikiDatabase.open(
                at: storeRoot.appendingPathComponent("index.sqlite"),
                embeddingDimension: settings.wikiEmbeddingDimension
            )
            let embedder: EmbeddingProvider? = ollamaBaseURL.map {
                OllamaEmbeddingProvider(
                    baseURL: $0,
                    modelID: settings.wikiEmbeddingModelID,
                    dimension: settings.wikiEmbeddingDimension
                )
            }
            let ctx = WikiContext(storeRoot: storeRoot, pool: pool, embedder: embedder)
            try ctx.bootstrapDirectoriesIfNeeded()

            let fw = WikiFileWatcher(context: ctx)
            try? fw.start()
            self.watcher = fw
            self.state = .ready(ctx)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    /// Force a full reindex. UI uses this for "Indexer maintenant".
    func reindexNow() async {
        guard let ctx = state.context else { return }
        _ = try? await ctx.makeIndexer().reindexAll()
    }

    private func tearDown() {
        watcher?.stop()
        watcher = nil
    }
}
