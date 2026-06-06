import Foundation
import Testing
import GRDB
@testable import TyKaoz

@Suite
struct WikiDatabaseTests {

    /// Phase 0 exit criterion: insert a 768-d vector, KNN, read result.
    /// Validates that the static sqlite-vec compilation + auto-extension
    /// registration actually wires through to a GRDB connection.
    @Test
    func roundTripVectorKNN() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let pool = try WikiDatabase.open(at: url)

        try await pool.write { db in
            try db.execute(sql: """
                INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                VALUES ('p1', 'wiki/test.md', 'Test', 'h1', datetime('now'), datetime('now'));
            """)
            try db.execute(sql: """
                INSERT INTO chunks (page_id, ordinal, text)
                VALUES ('p1', 0, 'hello world');
            """)
            let chunkID = db.lastInsertedRowID

            let probe = Array(repeating: Float(0.5), count: 768)
            try db.execute(sql: """
                INSERT INTO vec_chunks (chunk_id, embedding) VALUES (?, ?);
            """, arguments: [chunkID, Self.vectorBlob(probe)])
        }

        // KNN against an identical query vector → top-1 must be our chunk.
        let query = Array(repeating: Float(0.5), count: 768)
        let neighbours: [(chunkID: Int64, distance: Double)] = try await pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT chunk_id, distance
                FROM vec_chunks
                WHERE embedding MATCH ?
                ORDER BY distance
                LIMIT 5;
            """, arguments: [Self.vectorBlob(query)])
            .map { ($0["chunk_id"], $0["distance"]) }
        }

        #expect(neighbours.count == 1)
        #expect(neighbours.first?.chunkID != nil)
        #expect((neighbours.first?.distance ?? 1) < 0.001)
    }

    /// 3 vectors at known cosine distances from the query — KNN must
    /// return them in increasing distance order.
    @Test
    func knnRanksByDistance() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let pool = try WikiDatabase.open(at: url)

        // Three orthogonal-ish unit-ish vectors. We'll query close to v1.
        let v1 = Self.unitVector(seed: 1)
        let v2 = Self.unitVector(seed: 2)
        let v3 = Self.unitVector(seed: 3)
        let query = Self.blend(v1, with: v2, ratio: 0.95)  // very close to v1

        try await pool.write { db in
            for (i, vector) in [v1, v2, v3].enumerated() {
                let pageID = "p\(i)"
                try db.execute(sql: """
                    INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                    VALUES (?, ?, ?, 'h', datetime('now'), datetime('now'));
                """, arguments: [pageID, "wiki/\(pageID).md", "Page \(i)"])
                try db.execute(sql: """
                    INSERT INTO chunks (page_id, ordinal, text) VALUES (?, 0, ?);
                """, arguments: [pageID, "chunk \(i)"])
                let chunkID = db.lastInsertedRowID
                try db.execute(sql: """
                    INSERT INTO vec_chunks (chunk_id, embedding) VALUES (?, ?);
                """, arguments: [chunkID, Self.vectorBlob(vector)])
            }
        }

        let ranked: [Int64] = try await pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT chunk_id FROM vec_chunks
                WHERE embedding MATCH ?
                ORDER BY distance LIMIT 3;
            """, arguments: [Self.vectorBlob(query)])
            .map { $0["chunk_id"] }
        }

        #expect(ranked.count == 3)
        // First chunk (page p0, seed=1) must come back first since query
        // is a 95% blend toward v1.
        #expect(ranked.first == 1)
    }

    /// FTS5 contentless-backed virtual table must round-trip chunk text.
    @Test
    func fts5RoundTrip() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let pool = try WikiDatabase.open(at: url)

        try await pool.write { db in
            try db.execute(sql: """
                INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                VALUES ('p1', 'wiki/p1.md', 'P1', 'h', datetime('now'), datetime('now'));
            """)
            try db.execute(sql: """
                INSERT INTO chunks (page_id, ordinal, text) VALUES
                    ('p1', 0, 'le wiki LLM est une mémoire long-terme'),
                    ('p1', 1, 'le graphe relie les pages entre elles');
            """)
            // Triggers fill fts_chunks automatically on insert.
        }

        let hits: [Int64] = try await pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT rowid FROM fts_chunks WHERE fts_chunks MATCH 'mémoire';
            """).map { $0["rowid"] }
        }

        #expect(hits == [1])
    }

    /// `ON DELETE CASCADE` on the chunks FK must propagate to vec_chunks
    /// when the parent page is deleted.
    @Test
    func cascadeDeleteRemovesVectorRows() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let pool = try WikiDatabase.open(at: url)

        try await pool.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
            try db.execute(sql: """
                INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                VALUES ('p1', 'wiki/p1.md', 'P1', 'h', datetime('now'), datetime('now'));
            """)
            try db.execute(sql: """
                INSERT INTO chunks (page_id, ordinal, text) VALUES ('p1', 0, 't');
            """)
            let chunkID = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO vec_chunks (chunk_id, embedding) VALUES (?, ?);
            """, arguments: [chunkID, Self.vectorBlob(Self.unitVector(seed: 1))])

            try db.execute(sql: "DELETE FROM pages WHERE id = 'p1';")
        }

        try await pool.read { db in
            let chunkCount = try Int.fetchOne(db, sql: "SELECT count(*) FROM chunks;") ?? -1
            let vecCount = try Int.fetchOne(db, sql: "SELECT count(*) FROM vec_chunks;") ?? -1
            #expect(chunkCount == 0)
            #expect(vecCount == 0)
        }
    }

    /// Reopening an existing database must replay nothing (migration
    /// already applied) and keep the inserted data.
    @Test
    func reopensExistingDatabase() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let pool = try WikiDatabase.open(at: url)
            try await pool.write { db in
                try db.execute(sql: """
                    INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                    VALUES ('keeper', 'wiki/k.md', 'Keeper', 'h', datetime('now'), datetime('now'));
                """)
            }
        }

        // New pool, same file: data and schema must still be there.
        let pool = try WikiDatabase.open(at: url)
        let title: String? = try await pool.read { db in
            try String.fetchOne(db, sql: "SELECT title FROM pages WHERE id = 'keeper';")
        }
        #expect(title == "Keeper")
    }

    /// 1000 vectors at random positions in 768-d. Query a vector that
    /// matches one specific seed exactly; the matching chunk must come
    /// back first. Also measures the end-to-end KNN latency so we have a
    /// concrete number — anything past ~50 ms on M-series silicon is a
    /// red flag worth investigating before scaling further.
    @Test
    func knnAtScale1000() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let pool = try WikiDatabase.open(at: url)

        let target = 137  // arbitrary "needle" seed
        try await pool.write { db in
            for i in 0..<1_000 {
                let pageID = "p\(i)"
                try db.execute(sql: """
                    INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                    VALUES (?, ?, ?, 'h', datetime('now'), datetime('now'));
                """, arguments: [pageID, "wiki/\(pageID).md", "Page \(i)"])
                try db.execute(sql: """
                    INSERT INTO chunks (page_id, ordinal, text) VALUES (?, 0, ?);
                """, arguments: [pageID, "chunk text \(i)"])
                let chunkID = db.lastInsertedRowID
                try db.execute(sql: """
                    INSERT INTO vec_chunks (chunk_id, embedding) VALUES (?, ?);
                """, arguments: [chunkID, Self.vectorBlob(Self.unitVector(seed: i))])
            }
        }

        let query = Self.unitVector(seed: target)
        let start = Date()
        let firstChunkID: Int64? = try await pool.read { db in
            try Row.fetchOne(db, sql: """
                SELECT chunk_id FROM vec_chunks
                WHERE embedding MATCH ? ORDER BY distance LIMIT 1;
            """, arguments: [Self.vectorBlob(query)])?["chunk_id"]
        }
        let elapsed = Date().timeIntervalSince(start)
        print("knnAtScale1000: KNN over 1000 vectors took \(String(format: "%.4f", elapsed))s")

        // chunks.id is autoincrement starting at 1, target seed inserted
        // at iteration index `target`, so chunkID = target + 1.
        #expect(firstChunkID == Int64(target + 1))
        #expect(elapsed < 0.5)  // generous; M-series should be sub-50ms
    }

    /// Multiple parallel reads while a writer is mid-transaction. The pool
    /// must not deadlock and reads must see a consistent snapshot.
    @Test
    func concurrentReadsWhileWriting() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let pool = try WikiDatabase.open(at: url)

        // Seed with one page so reads have something to count.
        try await pool.write { db in
            try db.execute(sql: """
                INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                VALUES ('p0', 'wiki/p0.md', 'P0', 'h', datetime('now'), datetime('now'));
            """)
        }

        try await withThrowingTaskGroup(of: Int.self) { group in
            // One writer that adds 100 pages in a single transaction.
            group.addTask {
                try await pool.write { db in
                    for i in 1...100 {
                        try db.execute(sql: """
                            INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                            VALUES (?, ?, ?, 'h', datetime('now'), datetime('now'));
                        """, arguments: ["p\(i)", "wiki/p\(i).md", "P\(i)"])
                    }
                }
                return -1
            }
            // 16 parallel readers, each counting pages.
            for _ in 0..<16 {
                group.addTask {
                    try await pool.read { db in
                        try Int.fetchOne(db, sql: "SELECT count(*) FROM pages;") ?? -1
                    }
                }
            }

            var counts: [Int] = []
            for try await result in group {
                counts.append(result)
            }
            // Reader snapshots must be 1 (pre-write commit) or 101 (post)
            // — never partially-committed values like 47.
            let readerCounts = counts.filter { $0 != -1 }
            #expect(readerCounts.allSatisfy { $0 == 1 || $0 == 101 })
        }

        let finalCount = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM pages;") ?? 0
        }
        #expect(finalCount == 101)
    }

    /// chunks_au_fts must fire on UPDATE: rewriting a chunk's text means
    /// the old term stops matching and the new term starts matching.
    @Test
    func updateChunkRefreshesFTS() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let pool = try WikiDatabase.open(at: url)

        try await pool.write { db in
            try db.execute(sql: """
                INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                VALUES ('p1', 'wiki/p1.md', 'P1', 'h', datetime('now'), datetime('now'));
            """)
            try db.execute(sql: """
                INSERT INTO chunks (page_id, ordinal, text)
                VALUES ('p1', 0, 'avant');
            """)
        }

        // Sanity: 'avant' matches, 'après' doesn't.
        let preHitAvant = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM fts_chunks WHERE fts_chunks MATCH 'avant';") ?? 0
        }
        let preHitApres = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM fts_chunks WHERE fts_chunks MATCH 'après';") ?? 0
        }
        #expect(preHitAvant == 1)
        #expect(preHitApres == 0)

        try await pool.write { db in
            try db.execute(sql: "UPDATE chunks SET text = 'après' WHERE page_id = 'p1';")
        }

        let postHitAvant = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM fts_chunks WHERE fts_chunks MATCH 'avant';") ?? 0
        }
        let postHitApres = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM fts_chunks WHERE fts_chunks MATCH 'après';") ?? 0
        }
        #expect(postHitAvant == 0)
        #expect(postHitApres == 1)
    }

    /// Deleting a page with 100 chunks must wipe chunks, vec_chunks
    /// rows and fts_chunks entries — no orphans anywhere.
    @Test
    func bulkDeletionPropagatesEverywhere() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let pool = try WikiDatabase.open(at: url)

        try await pool.write { db in
            try db.execute(sql: """
                INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                VALUES ('p1', 'wiki/p1.md', 'P1', 'h', datetime('now'), datetime('now'));
            """)
            for i in 0..<100 {
                try db.execute(sql: """
                    INSERT INTO chunks (page_id, ordinal, text) VALUES ('p1', ?, ?);
                """, arguments: [i, "fragment \(i) du texte"])
                let chunkID = db.lastInsertedRowID
                try db.execute(sql: """
                    INSERT INTO vec_chunks (chunk_id, embedding) VALUES (?, ?);
                """, arguments: [chunkID, Self.vectorBlob(Self.unitVector(seed: i))])
            }
        }

        // Sanity before deletion.
        let preDelete: (Int, Int, Int) = try await pool.read { db in
            let c = try Int.fetchOne(db, sql: "SELECT count(*) FROM chunks;") ?? 0
            let v = try Int.fetchOne(db, sql: "SELECT count(*) FROM vec_chunks;") ?? 0
            let f = try Int.fetchOne(db, sql: "SELECT count(*) FROM fts_chunks WHERE fts_chunks MATCH 'fragment';") ?? 0
            return (c, v, f)
        }
        #expect(preDelete == (100, 100, 100))

        try await pool.write { db in
            try db.execute(sql: "DELETE FROM pages WHERE id = 'p1';")
        }

        let postDelete: (Int, Int, Int) = try await pool.read { db in
            let c = try Int.fetchOne(db, sql: "SELECT count(*) FROM chunks;") ?? -1
            let v = try Int.fetchOne(db, sql: "SELECT count(*) FROM vec_chunks;") ?? -1
            let f = try Int.fetchOne(db, sql: "SELECT count(*) FROM fts_chunks WHERE fts_chunks MATCH 'fragment';") ?? -1
            return (c, v, f)
        }
        #expect(postDelete == (0, 0, 0))
    }

    /// KNN over 10k vectors. sqlite-vec is brute-force exact search, so
    /// latency scales linearly with corpus size. Asserts a loose ceiling
    /// (<2 s on a debug build) and prints the actual number so we know
    /// when to start thinking about an ANN index.
    @Test
    func knnAtScale10000() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let pool = try WikiDatabase.open(at: url)

        let target = 7777
        let insertStart = Date()
        try await pool.write { db in
            try db.execute(sql: "INSERT INTO pages (id, path, title, content_hash, created_at, updated_at) VALUES ('p', 'wiki/p.md', 'P', 'h', datetime('now'), datetime('now'));")
            for i in 0..<10_000 {
                try db.execute(sql: """
                    INSERT INTO chunks (page_id, ordinal, text) VALUES ('p', ?, ?);
                """, arguments: [i, "c\(i)"])
                let chunkID = db.lastInsertedRowID
                try db.execute(sql: """
                    INSERT INTO vec_chunks (chunk_id, embedding) VALUES (?, ?);
                """, arguments: [chunkID, Self.vectorBlob(Self.unitVector(seed: i))])
            }
        }
        let insertElapsed = Date().timeIntervalSince(insertStart)
        print("knnAtScale10000: inserted 10k chunks+vectors in \(String(format: "%.3f", insertElapsed))s (= \(Int(10_000 / insertElapsed)) rows/s)")

        let query = Self.unitVector(seed: target)
        let knnStart = Date()
        let topChunkID: Int64? = try await pool.read { db in
            try Row.fetchOne(db, sql: """
                SELECT chunk_id FROM vec_chunks
                WHERE embedding MATCH ? ORDER BY distance LIMIT 1;
            """, arguments: [Self.vectorBlob(query)])?["chunk_id"]
        }
        let knnElapsed = Date().timeIntervalSince(knnStart)
        print("knnAtScale10000: KNN over 10k vectors in \(String(format: "%.4f", knnElapsed))s")

        #expect(topChunkID == Int64(target + 1))
        #expect(knnElapsed < 2.0)
    }

    /// Recursive CTE on `edges` — the actual graph-expansion query the
    /// Phase 3 finder will use. Seeds with 1000 pages randomly linked
    /// (avg ~5 outbound per page); verifies 1-hop and 2-hop reachable
    /// counts and prints latency.
    @Test
    func graphTraversalAt1000Pages() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let pool = try WikiDatabase.open(at: url)

        var rng = Self.SeededRNG(seed: 42)
        try await pool.write { db in
            for i in 0..<1_000 {
                try db.execute(sql: """
                    INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                    VALUES (?, ?, ?, 'h', datetime('now'), datetime('now'));
                """, arguments: ["p\(i)", "wiki/p\(i).md", "P\(i)"])
            }
            // ~5 outbound edges per page, all resolving (dst_page_id set).
            for i in 0..<1_000 {
                for _ in 0..<5 {
                    let target = rng.next(upperBound: 1_000)
                    if target == i { continue }
                    let dst = "p\(target)"
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO edges (src_page_id, dst_page_id, dst_title_raw, rel_type)
                        VALUES (?, ?, ?, 'link');
                    """, arguments: ["p\(i)", dst, "P\(target)"])
                }
            }
        }

        // 2-hop reachable set from p0, bidirectional (incoming + outgoing
        // edges count for hopping — that's the algorithm sketched in
        // PLAN_TYKAOZ_WIKI.md Phase 3).
        let cte = """
            WITH RECURSIVE reachable(page_id, depth) AS (
              SELECT 'p0', 0
              UNION
              SELECT CASE WHEN e.src_page_id = r.page_id THEN e.dst_page_id
                          ELSE e.src_page_id END, r.depth + 1
              FROM edges e JOIN reachable r
                ON (e.src_page_id = r.page_id OR e.dst_page_id = r.page_id)
              WHERE r.depth < 2 AND e.dst_page_id IS NOT NULL
            )
            SELECT count(DISTINCT page_id) FROM reachable;
        """
        let start = Date()
        let count = try await pool.read { db in
            try Int.fetchOne(db, sql: cte) ?? -1
        }
        let elapsed = Date().timeIntervalSince(start)
        print("graphTraversalAt1000Pages: 2-hop CTE from p0 found \(count) pages in \(String(format: "%.4f", elapsed))s")

        // Loose sanity: at 5 outbound × 1000 pages we expect the 2-hop
        // neighbourhood of any seed to be tens to low hundreds — not 1
        // (seed itself), not the entire graph.
        #expect(count > 5)
        #expect(count < 1_000)
        #expect(elapsed < 0.5)
    }

    /// Characterises the cost of re-indexing a single page: delete the
    /// existing chunks, re-insert with fresh embeddings, ensure FTS and
    /// vector tables follow. Phase 1's indexer will hammer this path.
    @Test
    func reindexOnePageAt100Chunks() async throws {
        let url = try Self.makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let pool = try WikiDatabase.open(at: url)

        // Seed page with 100 chunks.
        try await pool.write { db in
            try db.execute(sql: """
                INSERT INTO pages (id, path, title, content_hash, created_at, updated_at)
                VALUES ('p1', 'wiki/p1.md', 'P1', 'h', datetime('now'), datetime('now'));
            """)
            for i in 0..<100 {
                try db.execute(sql: """
                    INSERT INTO chunks (page_id, ordinal, text) VALUES ('p1', ?, ?);
                """, arguments: [i, "version1 chunk \(i)"])
                let chunkID = db.lastInsertedRowID
                try db.execute(sql: """
                    INSERT INTO vec_chunks (chunk_id, embedding) VALUES (?, ?);
                """, arguments: [chunkID, Self.vectorBlob(Self.unitVector(seed: i))])
            }
        }

        // Re-index: wipe chunks for this page, re-insert with fresh content
        // and fresh embeddings. Triggers handle vec_chunks + fts_chunks.
        let start = Date()
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM chunks WHERE page_id = 'p1';")
            for i in 0..<100 {
                try db.execute(sql: """
                    INSERT INTO chunks (page_id, ordinal, text) VALUES ('p1', ?, ?);
                """, arguments: [i, "version2 chunk \(i)"])
                let chunkID = db.lastInsertedRowID
                try db.execute(sql: """
                    INSERT INTO vec_chunks (chunk_id, embedding) VALUES (?, ?);
                """, arguments: [chunkID, Self.vectorBlob(Self.unitVector(seed: i + 10_000))])
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        print("reindexOnePageAt100Chunks: reindexed 100 chunks in \(String(format: "%.4f", elapsed))s")

        // Verify the rewrite happened: old term no longer matches, new
        // does, and vec_chunks count is back to 100.
        let counts: (oldHits: Int, newHits: Int, vec: Int) = try await pool.read { db in
            let oldHits = try Int.fetchOne(db, sql: "SELECT count(*) FROM fts_chunks WHERE fts_chunks MATCH 'version1';") ?? -1
            let newHits = try Int.fetchOne(db, sql: "SELECT count(*) FROM fts_chunks WHERE fts_chunks MATCH 'version2';") ?? -1
            let vec = try Int.fetchOne(db, sql: "SELECT count(*) FROM vec_chunks;") ?? -1
            return (oldHits, newHits, vec)
        }
        #expect(counts.oldHits == 0)
        #expect(counts.newHits == 100)
        #expect(counts.vec == 100)
        #expect(elapsed < 1.0)
    }

    // MARK: - Helpers

    private static func makeTemporaryDatabaseURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WikiDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("wiki.sqlite")
    }

    /// vec0 expects a contiguous little-endian Float32 blob.
    private static func vectorBlob(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Deterministic 768-dim vector with a per-seed unique pseudo-random
    /// signature. LCG ensures collisions only at very large seed counts —
    /// suitable for KNN ranking tests up to thousands of vectors.
    private static func unitVector(seed: Int) -> [Float] {
        var rng = UInt32(bitPattern: Int32(truncatingIfNeeded: seed &+ 1))
        var v = [Float](repeating: 0, count: 768)
        for i in 0..<768 {
            rng = rng &* 1_664_525 &+ 1_013_904_223
            v[i] = Float(rng & 0xFFFF) / Float(0xFFFF)
        }
        return v
    }

    /// Returns `ratio * a + (1 - ratio) * b`, dim-wise.
    private static func blend(_ a: [Float], with b: [Float], ratio: Float) -> [Float] {
        zip(a, b).map { ratio * $0 + (1 - ratio) * $1 }
    }

    /// Numerical Recipes LCG. Deterministic per-seed, sufficient for
    /// shuffling test fixtures without a Foundation dependency.
    private struct SeededRNG {
        private var state: UInt32
        init(seed: Int) { state = UInt32(bitPattern: Int32(truncatingIfNeeded: seed &+ 1)) }
        mutating func next(upperBound: Int) -> Int {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Int(state) % upperBound
        }
    }
}
