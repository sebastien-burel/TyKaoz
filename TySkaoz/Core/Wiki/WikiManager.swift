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
    /// The Ollama URL + model the current context was built with.
    /// `reconcile()` rebuilds when these change.
    private(set) var activeOllamaURL: URL?
    private(set) var activeModelID: String?
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
            activeOllamaURL = nil
            activeModelID = nil
            return
        }

        // If we're already ready AND the embedder config hasn't moved,
        // there's nothing to do. The embedding dimension is locked to
        // the DB schema, so we don't rebuild on dim changes — a
        // rebuild-vectoriel migration covers that path.
        if case .ready = state,
           activeOllamaURL == ollamaBaseURL,
           activeModelID == settings.wikiEmbeddingModelID {
            return
        }

        // Embedder config moved — tear down and rebuild so the new
        // OllamaEmbeddingProvider gets the current URL/model.
        tearDown()

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
            self.activeOllamaURL = ollamaBaseURL
            self.activeModelID = settings.wikiEmbeddingModelID
        } catch {
            state = .failed(message: error.localizedDescription)
            activeOllamaURL = nil
            activeModelID = nil
        }
    }

    /// Force a full reindex. UI uses this for "Indexer maintenant".
    func reindexNow() async {
        guard let ctx = state.context else { return }
        _ = try? await ctx.makeIndexer().reindexAll()
    }

    /// Nukes the SQLite index and rebuilds it from scratch against the
    /// current embedding dimension. Used when the user changes
    /// `wikiEmbeddingDimension` (locked into the schema at first open
    /// — bge-m3 = 1024, nomic-embed-text = 768) and the existing
    /// vectors can't be mixed.
    ///
    /// Safe because the markdown under `wiki/` is canonical: the
    /// index is derived data, reconstructible at any time.
    func rebuildIndex(settings: AppSettings, ollamaBaseURL: URL?) async {
        tearDown()
        state = .disabled
        activeOllamaURL = nil
        activeModelID = nil

        let storeRoot = Self.defaultStoreRoot()
        let dbURL = storeRoot.appendingPathComponent("index.sqlite")
        try? FileManager.default.removeItem(at: dbURL)
        // GRDB writes -wal and -shm files next to the DB; clear them
        // too, otherwise the next open will see a stale journal.
        for suffix in ["-wal", "-shm"] {
            let extra = dbURL.deletingPathExtension()
                .appendingPathExtension("sqlite\(suffix)")
            try? FileManager.default.removeItem(at: extra)
        }

        reconcile(settings: settings, ollamaBaseURL: ollamaBaseURL)
        await reindexNow()
    }

    private func tearDown() {
        watcher?.stop()
        watcher = nil
    }
}
