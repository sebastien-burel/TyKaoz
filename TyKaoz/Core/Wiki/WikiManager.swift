import Foundation
import TyKaozKitMLX
import TyKaozKit
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

    /// Where the configured embedder is in its life-cycle. Only
    /// meaningful for providers that require a heavy load (MLX
    /// downloads + memory-maps weights); network-only providers
    /// (Ollama, Local OpenAI) sit at `.ready` immediately.
    enum EmbedderLoadState: Equatable {
        case idle               // no embedder configured, or not started yet
        case downloading(progress: Double)  // 0.0…1.0
        case loading            // model on disk, mmap'ing into Metal
        case ready
        case failed(message: String)
    }

    /// Recommended defaults for each embedder runtime. The wiki
    /// settings UI uses these to auto-fill the model ID / dimension
    /// when the user switches the picker — saves the "did you
    /// remember to also change the model name?" trap.
    struct EmbedderDefaults {
        let modelID: String
        let dimension: Int

        static func forProvider(_ providerID: String) -> EmbedderDefaults {
            switch providerID {
            case "mlx":
                return .init(modelID: "TyKaoz/bge-m3-4bit", dimension: 1024)
            case "ollama":
                return .init(modelID: "nomic-embed-text", dimension: 768)
            default:
                return .init(modelID: "nomic-embed-text", dimension: 768)
            }
        }
    }

    private(set) var state: State = .disabled
    private(set) var embedderLoadState: EmbedderLoadState = .idle
    @ObservationIgnored private var preloadTask: Task<Void, Never>?
    /// Snapshot of the embedder config the current context was built
    /// with. `reconcile()` rebuilds when these drift.
    private(set) var activeProviderID: String?
    private(set) var activeEmbedderURL: URL?
    private(set) var activeModelID: String?

    /// Backwards-compat alias surfaced in the wiki settings panel.
    var activeOllamaURL: URL? {
        activeProviderID == "ollama" ? activeEmbedderURL : nil
    }
    /// Bumped after every successful (re)index. UI views observe it
    /// via `.task(id: wiki.indexRevision)` to refresh their snapshot.
    private(set) var indexRevision: Int = 0
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
        // All app data lives under TyKaoz/ (conversations, memories,
        // plugins…); the wiki joins it there instead of sitting beside it.
        let root = appSupport.appendingPathComponent("TyKaoz/wiki-store", isDirectory: true)
        migrateLegacyStoreIfNeeded(to: root, appSupport: appSupport)
        return root
    }

    /// One-time move of the old top-level `wiki-store/` into `TyKaoz/`.
    /// No-op once migrated (runs before the DB is opened, so moving the
    /// whole directory — index.sqlite + wal/shm together — is safe).
    private static func migrateLegacyStoreIfNeeded(to newRoot: URL, appSupport: URL) {
        let fm = FileManager.default
        let legacy = appSupport.appendingPathComponent("wiki-store", isDirectory: true)
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: newRoot.path) else { return }
        try? fm.createDirectory(
            at: newRoot.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? fm.moveItem(at: legacy, to: newRoot)
    }

    /// Builds (or rebuilds) the context based on the current settings.
    /// Idempotent: if the manager is already ready with the same
    /// configuration, this is a no-op.
    func reconcile(settings: AppSettings) {
        guard settings.wikiEnabled else {
            tearDown()
            state = .disabled
            activeProviderID = nil
            activeEmbedderURL = nil
            activeModelID = nil
            return
        }

        let providerID = settings.wikiEmbeddingProviderID
        let embedderURL = Self.embedderURL(for: providerID, settings: settings)

        // If we're already ready AND the embedder config hasn't moved,
        // there's nothing to do. The embedding dimension is locked to
        // the DB schema, so we don't rebuild on dim changes — a
        // rebuild-vectoriel migration covers that path.
        if case .ready = state,
           activeProviderID == providerID,
           activeEmbedderURL == embedderURL,
           activeModelID == settings.wikiEmbeddingModelID {
            return
        }

        // Embedder config moved — tear down and rebuild.
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
            let embedder: EmbeddingProvider? = Self.makeEmbedder(
                providerID: providerID,
                url: embedderURL,
                settings: settings
            )
            let ctx = WikiContext(storeRoot: storeRoot, pool: pool, embedder: embedder)
            try ctx.bootstrapDirectoriesIfNeeded()
            try ctx.bootstrapSchemaFileIfNeeded()

            let fw = WikiFileWatcher(context: ctx)
            fw.onIndexed = { [weak self] in
                self?.indexRevision &+= 1
            }
            try? fw.start()
            self.watcher = fw
            self.state = .ready(ctx)
            self.activeProviderID = providerID
            self.activeEmbedderURL = embedderURL
            self.activeModelID = settings.wikiEmbeddingModelID
            self.startEmbedderPreload(providerID: providerID, modelID: settings.wikiEmbeddingModelID)
        } catch {
            state = .failed(message: error.localizedDescription)
            activeProviderID = nil
            activeEmbedderURL = nil
            activeModelID = nil
            embedderLoadState = .failed(message: error.localizedDescription)
        }
    }

    /// For network providers (Ollama, Local OpenAI) the embedder is
    /// always ready — no warm-up needed. For MLX we kick off a
    /// background download/load so the first `embed()` call doesn't
    /// have to wait, and so the settings UI can show progress.
    private func startEmbedderPreload(providerID: String, modelID: String) {
        preloadTask?.cancel()
        guard providerID == "mlx" else {
            embedderLoadState = .ready
            return
        }
        embedderLoadState = .downloading(progress: 0)
        preloadTask = Task { [weak self] in
            do {
                _ = try await MLXModelStore.shared.download(modelID: modelID) { @MainActor progress in
                    self?.embedderLoadState = .downloading(progress: progress)
                }
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.embedderLoadState = .loading
                }
                // The actor will load the model on its first embed.
                // Trigger a no-op embed to warm the Metal queue
                // (and reveal any architecture-mismatch failures
                // upfront rather than in the middle of a search).
                let actor = await MLXEmbeddingActor.shared(for: modelID)
                _ = try await actor.embed([" "])
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.embedderLoadState = .ready
                }
            } catch is CancellationError {
                // Reconciled away before we finished — silent.
            } catch {
                await MainActor.run {
                    self?.embedderLoadState = .failed(
                        message: "Erreur MLX (\(modelID)) : \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    /// Picks the URL the configured embedding provider should hit.
    /// Returns `nil` for in-process providers (MLX) — the embedder
    /// runs locally and doesn't need a base URL.
    static func embedderURL(for providerID: String, settings: AppSettings) -> URL? {
        switch providerID {
        case "mlx":         return nil
        case "ollama":      return settings.serverURL
        default:            return settings.serverURL
        }
    }

    /// Constructs the right concrete `EmbeddingProvider` for the chosen
    /// runtime. Returns nil when a network-bound runtime is missing
    /// its prerequisite (URL, key…). MLX has no URL prerequisite —
    /// its prerequisite is the model on disk, validated at first
    /// `embed()` call inside the actor.
    private static func makeEmbedder(
        providerID: String,
        url: URL?,
        settings: AppSettings
    ) -> EmbeddingProvider? {
        switch providerID {
        case "mlx":
            return MLXEmbeddingProvider(
                modelID: settings.wikiEmbeddingModelID,
                dimension: settings.wikiEmbeddingDimension
            )
        default:
            guard let url else { return nil }
            return OllamaEmbeddingProvider(
                baseURL: url,
                modelID: settings.wikiEmbeddingModelID,
                dimension: settings.wikiEmbeddingDimension
            )
        }
    }

    /// Force a full reindex. UI uses this for "Indexer maintenant".
    func reindexNow() async {
        guard let ctx = state.context else { return }
        _ = try? await ctx.reindexAll()
        indexRevision &+= 1
    }

    /// Nukes the SQLite index and rebuilds it from scratch against the
    /// current embedding dimension. Used when the user changes
    /// `wikiEmbeddingDimension` (locked into the schema at first open
    /// — bge-m3 = 1024, nomic-embed-text = 768) and the existing
    /// vectors can't be mixed.
    ///
    /// Safe because the markdown under `wiki/` is canonical: the
    /// index is derived data, reconstructible at any time.
    func rebuildIndex(settings: AppSettings) async {
        tearDown()
        state = .disabled
        activeProviderID = nil
        activeEmbedderURL = nil
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

        reconcile(settings: settings)
        await reindexNow()
        indexRevision &+= 1
    }

    /// Full content reset: deletes every wiki page and the journal
    /// (`log.md`), then rebuilds the now-empty index (which also
    /// regenerates an empty `index.md`). **Kept**: the imported sources
    /// under `raw/` (the user's inputs) and the conventions `AGENTS.md`.
    /// Destructive — the UI confirms first. The deletion is git-committed,
    /// so it stays recoverable via `git` in the store.
    func resetWiki(settings: AppSettings) async {
        let wikiRoot = Self.defaultStoreRoot().appendingPathComponent("wiki", isDirectory: true)
        let fm = FileManager.default
        // Pages can live in subfolders (concepts/, family/…), so recurse.
        let keep = wikiRoot.appendingPathComponent("AGENTS.md").standardizedFileURL.path
        if let enumerator = fm.enumerator(
            at: wikiRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator
            where url.pathExtension.lowercased() == "md"
                && url.standardizedFileURL.path != keep {
                try? fm.removeItem(at: url)
            }
        }
        // Drop the now-empty subfolders so the tree stays clean.
        if let entries = try? fm.contentsOfDirectory(
            at: wikiRoot, includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for url in entries {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      let sub = try? fm.contentsOfDirectory(atPath: url.path), sub.isEmpty
                else { continue }
                try? fm.removeItem(at: url)
            }
        }
        GitRunner.commit(message: "reset wiki", in: wikiRoot)
        await rebuildIndex(settings: settings)
    }

    private func tearDown() {
        watcher?.stop()
        watcher = nil
        preloadTask?.cancel()
        preloadTask = nil
        embedderLoadState = .idle
    }
}
