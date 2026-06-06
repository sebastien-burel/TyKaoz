import Foundation
import GRDB

/// Bundles every piece the wiki tools need: the on-disk store layout,
/// the SQLite index, and (when configured) the embedder. Constructed
/// once at app startup and threaded into each tool.
///
/// Layout per PLAN_TYKAOZ_WIKI.md:
///   storeRoot/
///   ├── raw/    immutable sources
///   └── wiki/   canonical markdown
struct WikiContext: Sendable {
    let storeRoot: URL
    let pool: DatabasePool
    let embedder: (any EmbeddingProvider)?

    init(storeRoot: URL, pool: DatabasePool, embedder: (any EmbeddingProvider)? = nil) {
        self.storeRoot = storeRoot
        self.pool = pool
        self.embedder = embedder
    }

    var wikiRoot: URL {
        storeRoot.appendingPathComponent("wiki", isDirectory: true)
    }

    var rawRoot: URL {
        storeRoot.appendingPathComponent("raw", isDirectory: true)
    }

    /// Ensures `wiki/` and `raw/` exist on disk. Safe to call repeatedly.
    func bootstrapDirectoriesIfNeeded() throws {
        let fm = FileManager.default
        for dir in [wikiRoot, rawRoot] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    func makeIndexer() -> Indexer {
        Indexer(wikiRoot: wikiRoot, pool: pool, embedder: embedder)
    }
}
