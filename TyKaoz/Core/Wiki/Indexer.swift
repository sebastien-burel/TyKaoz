import Foundation
import GRDB

enum IndexerError: Error, LocalizedError, Equatable {
    case embeddingCountMismatch(expected: Int, got: Int)
    case embeddingDimensionMismatch(expected: Int, got: Int)

    var errorDescription: String? {
        switch self {
        case .embeddingCountMismatch(let e, let g):
            return "Embedder a renvoyé \(g) vecteurs pour \(e) chunks."
        case .embeddingDimensionMismatch(let e, let g):
            return "Vecteur de dimension \(g), attendu \(e) (cf. WikiSchemaV1)."
        }
    }
}

/// Result of indexing a single page.
enum IndexOutcome: Hashable {
    case added
    case updated
    case unchanged
    case removed
}

/// Aggregate result of `reindexAll`. Counts what happened across the
/// whole `wiki/` tree.
struct IndexReport: Hashable {
    var added = 0
    var updated = 0
    var unchanged = 0
    var removed = 0

    mutating func record(_ outcome: IndexOutcome) {
        switch outcome {
        case .added:     added += 1
        case .updated:   updated += 1
        case .unchanged: unchanged += 1
        case .removed:   removed += 1
        }
    }
}

/// Walks the `wiki/` markdown tree and brings the SQLite index in sync.
///
/// Strict one-way data flow per PLAN_TYKAOZ_WIKI: disk is canonical,
/// SQLite is derived. The indexer reads `.md` files, computes a
/// content hash, skips unchanged pages, upserts changed ones, and
/// reconciles deletions at the end.
///
/// `embedder` is optional during Phase 1 because the real conformer
/// arrives in Phase 5. When nil, chunks are still indexed (FTS works
/// via triggers); `vec_chunks` simply stays empty until embeddings
/// are wired in.
struct Indexer {
    let wikiRoot: URL
    let pool: DatabasePool
    let embedder: EmbeddingProvider?

    init(wikiRoot: URL, pool: DatabasePool, embedder: EmbeddingProvider? = nil) {
        self.wikiRoot = wikiRoot
        self.pool = pool
        self.embedder = embedder
    }

    /// Scans the entire `wiki/` tree, indexes every `.md` file and
    /// removes DB pages whose source files have disappeared.
    func reindexAll() async throws -> IndexReport {
        var report = IndexReport()
        let files = try discoverMarkdownFiles()
        var seenIDs: Set<String> = []

        // First pass: build the title→id index so wikilink resolution
        // works even for files we haven't visited yet. This is the
        // resolver passed to edge insertion below.
        var titleToID: [String: String] = [:]
        var parsed: [(relativePath: String, page: ParsedPage)] = []
        for url in files {
            let content = try String(contentsOf: url, encoding: .utf8)
            let relativePath = url.path
                .replacingOccurrences(of: wikiRoot.path + "/", with: "")
            let page = MarkdownParser.parse(content, path: relativePath)
            parsed.append((relativePath, page))
            titleToID[page.title] = page.id
            seenIDs.insert(page.id)
        }

        // Second pass: pages + chunks for every parsed file, all inside
        // one write tx so the edges insert (third pass below) sees a DB
        // where every referenced target page already exists. Doing edges
        // per-page would trip the `edges.dst_page_id → pages.id` FK as
        // soon as a link points to a page later in the iteration order.
        let outcomes: [String: IndexOutcome]
        let embedTargets: [String: [EmbedTarget]]
        (outcomes, embedTargets) = try await pool.write { db in
            var outcomes: [String: IndexOutcome] = [:]
            var targets: [String: [EmbedTarget]] = [:]
            for (relativePath, page) in parsed {
                let (outcome, chunkTargets) = try writePageAndChunks(
                    db, page: page, relativePath: relativePath
                )
                outcomes[page.id] = outcome
                if outcome != .unchanged {
                    targets[page.id] = chunkTargets
                }
            }
            // Edges as a final sub-pass — every page exists by now.
            for (_, page) in parsed where outcomes[page.id] != .unchanged {
                try writeEdges(db, page: page, titleToID: titleToID)
            }
            return (outcomes, targets)
        }
        for outcome in outcomes.values {
            report.record(outcome)
        }

        // Embeddings outside the writer lock — network/model latency.
        for (_, page) in parsed {
            if let pageTargets = embedTargets[page.id], !pageTargets.isEmpty {
                try await embedAndStore(pageTargets)
            }
        }

        // Reconcile: anything in DB that's no longer on disk gets cascaded.
        let removed = try await pruneMissing(keeping: seenIDs)
        for _ in 0..<removed { report.record(.removed) }

        return report
    }

    /// Pairs of (chunkID, text) the caller still needs to embed once the
    /// write transaction has released the writer lock.
    private typealias EmbedTarget = (chunkID: Int64, text: String)

    /// Pass 1 for a single page — upsert `pages` row, replace chunks.
    /// Skips when the content hash matches what's already indexed.
    /// Edges are intentionally NOT touched here; they run in pass 2
    /// once every page is in the DB.
    private func writePageAndChunks(
        _ db: Database,
        page: ParsedPage,
        relativePath: String
    ) throws -> (IndexOutcome, [EmbedTarget]) {
        let existingHash = try String.fetchOne(
            db,
            sql: "SELECT content_hash FROM pages WHERE id = ?",
            arguments: [page.id]
        )
        if existingHash == page.contentHash {
            return (.unchanged, [])
        }

        let outcome: IndexOutcome = existingHash == nil ? .added : .updated
        let now = Date()

        try db.execute(sql: """
            INSERT INTO pages (id, path, title, type, summary,
                               content_hash, created_at, updated_at)
            VALUES (?, ?, ?, ?, NULL, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                path = excluded.path,
                title = excluded.title,
                type = excluded.type,
                content_hash = excluded.content_hash,
                updated_at = excluded.updated_at;
        """, arguments: [
            page.id, relativePath, page.title, page.type,
            page.contentHash, now, now
        ])

        try db.execute(sql: "DELETE FROM chunks WHERE page_id = ?;",
                       arguments: [page.id])
        var chunkIDs: [Int64] = []
        for chunk in page.chunks {
            let headingPath = Self.encodeHeadingPath(chunk.headingPath)
            try db.execute(sql: """
                INSERT INTO chunks (page_id, ordinal, heading_path, text)
                VALUES (?, ?, ?, ?);
            """, arguments: [page.id, chunk.ordinal, headingPath, chunk.text])
            chunkIDs.append(db.lastInsertedRowID)
        }

        let targets: [EmbedTarget] = zip(chunkIDs, page.chunks.map(\.text))
            .map { EmbedTarget(chunkID: $0, text: $1) }
        return (outcome, targets)
    }

    /// Pass 2: edges, resolved against the in-memory `titleToID` map and
    /// the pages already written in pass 1. By the time this runs every
    /// page exists in the DB, so the FK on `edges.dst_page_id` is happy.
    private func writeEdges(
        _ db: Database,
        page: ParsedPage,
        titleToID: [String: String]
    ) throws {
        try db.execute(sql: "DELETE FROM edges WHERE src_page_id = ?;",
                       arguments: [page.id])
        for link in page.wikilinks {
            let resolvedID: String?
            if try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM pages WHERE id = ?);",
                arguments: [link.raw]
            ) == true {
                resolvedID = link.raw
            } else {
                resolvedID = titleToID[link.raw]
            }
            try db.execute(sql: """
                INSERT OR IGNORE INTO edges
                    (src_page_id, dst_page_id, dst_title_raw, rel_type)
                VALUES (?, ?, ?, 'link');
            """, arguments: [page.id, resolvedID, link.raw])
        }
    }

    /// Embeds the given chunks in one batch and writes them to
    /// `vec_chunks`. A no-op when no embedder is configured — Phase 1
    /// still keeps chunks + FTS in sync, vector search just stays empty
    /// until Phase 5 plugs Ollama in.
    private func embedAndStore(_ targets: [EmbedTarget]) async throws {
        guard let embedder else { return }
        let vectors = try await embedder.embed(targets.map(\.text))
        guard vectors.count == targets.count else {
            throw IndexerError.embeddingCountMismatch(
                expected: targets.count, got: vectors.count
            )
        }

        try await pool.write { db in
            for (target, vector) in zip(targets, vectors) {
                guard vector.count == embedder.dimension else {
                    throw IndexerError.embeddingDimensionMismatch(
                        expected: embedder.dimension, got: vector.count
                    )
                }
                let blob = vector.withUnsafeBufferPointer { Data(buffer: $0) }
                try db.execute(sql: """
                    INSERT INTO vec_chunks (chunk_id, embedding)
                    VALUES (?, ?);
                """, arguments: [target.chunkID, blob])
            }
        }
    }

    /// Deletes DB pages whose ids are no longer present on disk.
    /// Returns the number of removed pages.
    private func pruneMissing(keeping seenIDs: Set<String>) async throws -> Int {
        try await pool.write { db in
            let allIDs = try String.fetchAll(db, sql: "SELECT id FROM pages;")
            let toDelete = allIDs.filter { !seenIDs.contains($0) }
            for id in toDelete {
                try db.execute(sql: "DELETE FROM pages WHERE id = ?;",
                               arguments: [id])
            }
            return toDelete.count
        }
    }

    /// Lists `.md` files in `wikiRoot`, recursively, sorted for
    /// deterministic ordering across runs (helps tests).
    private func discoverMarkdownFiles() throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: wikiRoot.path) else { return [] }

        var urls: [URL] = []
        let enumerator = fm.enumerator(
            at: wikiRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "md" else { continue }
            urls.append(url)
        }
        return urls.sorted { $0.path < $1.path }
    }

    /// JSON-encode the heading breadcrumb so SQL queries on
    /// `chunks.heading_path` can pull it out with json_extract if needed.
    private static func encodeHeadingPath(_ path: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: path),
              let s = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return s
    }
}
