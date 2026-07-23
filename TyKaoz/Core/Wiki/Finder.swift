import Foundation
import KaozKit
import GRDB

/// One retrieval hit. Seed pages carry the actual matched chunk as
/// `snippet`; graph-expanded neighbours fall back to the page summary
/// (or the title when no summary is set yet).
struct Retrieved: Hashable {
    let pageID: String
    let title: String
    let snippet: String
    let headingPath: [String]?
    /// 0 for direct semantic/lexical hits, ≥1 for graph-expanded
    /// neighbours.
    let hops: Int
    let score: Double
}

/// Hybrid retrieval: KNN over `vec_chunks` + BM25 over `fts_chunks`,
/// fused via Reciprocal Rank Fusion at the page level, then
/// graph-expanded 1–2 hops via `edges`, then re-scored.
///
/// The exact algorithm follows PLAN_TYKAOZ_WIKI.md Phase 3. Tunables
/// are static constants so tests can replicate the production setup
/// deterministically.
struct Finder {
    let pool: DatabasePool
    let embedder: EmbeddingProvider

    // MARK: - Tunables (PLAN_TYKAOZ_WIKI Phase 3 §1–3)

    /// Seed sizes — how many candidate chunks per modality.
    static let seedKNN = 20
    static let seedFTS = 20
    /// How many top fused pages to feed into graph expansion.
    static let topSeedPages = 8
    /// 0 = seed, 1 or 2 = expanded neighbour.
    static let maxHops = 2
    /// RRF damping constant. 60 is the canonical default; lower would
    /// over-reward top-ranked items.
    static let rrfK = 60.0
    /// Final result count when caller doesn't ask for one.
    static let defaultLimit = 8

    // MARK: - Entry point

    func search(_ query: String, limit: Int = defaultLimit) async throws -> [Retrieved] {
        let queryVector = try await embedder.embed([query])[0]
        let queryBlob = queryVector.withUnsafeBufferPointer { Data(buffer: $0) }

        return try await pool.read { db in
            // 1. Seeds: KNN ∪ BM25, fused at the page level by RRF.
            //
            // vec0 always returns its full LIMIT regardless of distance,
            // so on small corpora KNN dumps every page into the seed
            // pool — drowning out the lexical signal and erasing the
            // notion of "graph expansion neighbour". We filter the KNN
            // side against a noise-floor derived from the distribution
            // of returned similarities: a page only earns a KNN seed
            // slot if it stands clearly above the median; everything
            // else can only get in via a BM25 hit.
            let knnHits = try Self.fetchKNNHits(db, queryBlob: queryBlob)
            let ftsHits = try Self.fetchFTSHits(db, query: query)
            let similarities = Self.bestSimilarities(knn: knnHits)
            let bm25Ranks = Self.bestRanksByPage(fts: ftsHits)

            let noiseFloor = Self.noiseFloor(similarities: similarities)
            let knnHitsAboveFloor = knnHits.filter {
                (similarities[$0.pageID] ?? 0) > noiseFloor
            }
            let seedScores = Self.fuseByRRF(knn: knnHitsAboveFloor, fts: ftsHits)
            let seedPageIDs = Array(
                seedScores.sorted(by: { $0.value > $1.value })
                    .prefix(Self.topSeedPages)
                    .map(\.key)
            )
            guard !seedPageIDs.isEmpty else { return [] }

            // 2. Graph expansion 0..maxHops from seeds.
            let hopsByPage = try Self.expandGraph(db, seeds: seedPageIDs)

            // 3. Per-page metadata (title, summary, updated_at).
            let candidatePages = Array(hopsByPage.keys)
            let pageInfo = try Self.fetchPageInfo(db, pageIDs: candidatePages)

            // 4. Connection count: how many seeds each candidate touches.
            let connectionCounts = try Self.fetchConnectionCounts(
                db, candidates: candidatePages, seeds: seedPageIDs
            )

            // 5. Seed snippets keyed by page — best matched chunk per page.
            let seedSnippets = Self.buildSeedSnippets(
                knn: knnHitsAboveFloor, fts: ftsHits
            )

            // 6. Score + assemble.
            // The plan's formula (PLAN_TYKAOZ_WIKI Phase 3 §3) lists
            // `sim + 1/(1+hops) + nb_connexions_graines + fraîcheur`.
            // We tweak two things in practice:
            //   - `log(1+conn) * 0.3` instead of raw count — raw connection
            //     count explodes on hub pages and drowns out everything
            //     else; the log + low weight keeps connectivity as a
            //     tiebreaker.
            //   - explicit BM25 rank bonus `1/(1+bm25_rank)` so a page
            //     that lexical search rates #1 gets a real push, not just
            //     a foot in the seed door.
            let now = Date()
            let scored = candidatePages.compactMap { id -> (Retrieved, Double)? in
                guard let info = pageInfo[id] else { return nil }
                let hops = hopsByPage[id] ?? Self.maxHops
                let sim = similarities[id] ?? 0
                let connections = connectionCounts[id] ?? 0
                let recency = Self.recencyScore(updatedAt: info.updatedAt, reference: now)
                let bm25Boost = bm25Ranks[id].map { 1.0 / Double(1 + $0) } ?? 0
                let score = sim
                    + 1.0 / Double(1 + hops)
                    + 0.3 * log(1.0 + Double(connections))
                    + recency
                    + bm25Boost

                let snippet: String
                let headingPath: [String]?
                if hops == 0, let hit = seedSnippets[id] {
                    snippet = Self.truncate(hit.text)
                    headingPath = Self.decodeHeadingPath(hit.headingPath)
                } else {
                    snippet = info.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? info.summary!
                        : info.title
                    headingPath = nil
                }

                let retrieved = Retrieved(
                    pageID: id,
                    title: info.title,
                    snippet: snippet,
                    headingPath: headingPath,
                    hops: hops,
                    score: score
                )
                return (retrieved, score)
            }

            return scored
                .sorted(by: { $0.1 > $1.1 })
                .prefix(limit)
                .map(\.0)
        }
    }

    // MARK: - Seeds

    /// One seed hit per chunk, used to feed both RRF and snippet lookup.
    struct Hit: Hashable {
        let pageID: String
        let chunkID: Int64
        let text: String
        let headingPath: String?
        /// 1-based position in the ranking it came from.
        let rank: Int
        /// vec0 distance (KNN) or BM25 score (FTS). Smaller = better
        /// in both cases.
        let metric: Double
    }

    /// `vec0` rejects ORDER BY ... LIMIT applied after a join — the
    /// LIMIT has to sit inside the MATCH subquery. Same lesson as the
    /// Phase 5 integration test.
    static func fetchKNNHits(_ db: Database, queryBlob: Data) throws -> [Hit] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT c.page_id, c.id AS chunk_id, c.text, c.heading_path, v.distance
            FROM (
                SELECT chunk_id, distance FROM vec_chunks
                WHERE embedding MATCH ? ORDER BY distance LIMIT ?
            ) v
            JOIN chunks c ON c.id = v.chunk_id;
        """, arguments: [queryBlob, seedKNN])
        return rows.enumerated().map { (i, row) in
            Hit(
                pageID: row["page_id"],
                chunkID: row["chunk_id"],
                text: row["text"],
                headingPath: row["heading_path"],
                rank: i + 1,
                metric: row["distance"]
            )
        }
    }

    /// FTS5 bm25() returns a score where lower = more relevant. Match
    /// returns nothing for an empty query, which is fine.
    static func fetchFTSHits(_ db: Database, query: String) throws -> [Hit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // FTS5 MATCH parses its operand as a query expression — quotes
        // and special chars need escaping. We wrap the raw query in
        // double quotes to force a phrase match, doubling any inner
        // quote as required by FTS5.
        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\"\"")
        let ftsQuery = "\"\(escaped)\""

        let rows = try Row.fetchAll(db, sql: """
            SELECT c.page_id, c.id AS chunk_id, c.text, c.heading_path,
                   bm25(fts_chunks) AS bm25_score
            FROM fts_chunks
            JOIN chunks c ON c.id = fts_chunks.rowid
            WHERE fts_chunks MATCH ?
            ORDER BY bm25_score LIMIT ?;
        """, arguments: [ftsQuery, seedFTS])
        return rows.enumerated().map { (i, row) in
            Hit(
                pageID: row["page_id"],
                chunkID: row["chunk_id"],
                text: row["text"],
                headingPath: row["heading_path"],
                rank: i + 1,
                metric: row["bm25_score"]
            )
        }
    }

    /// Reciprocal Rank Fusion at the page level. For each ranking,
    /// each page's best rank contributes `1 / (rrfK + rank)`. Adding
    /// the contributions across rankings gives a fused page score
    /// that doesn't depend on the underlying metric scales.
    static func fuseByRRF(knn: [Hit], fts: [Hit]) -> [String: Double] {
        var bestKNNRank: [String: Int] = [:]
        for hit in knn where bestKNNRank[hit.pageID] == nil {
            bestKNNRank[hit.pageID] = hit.rank
        }
        var bestFTSRank: [String: Int] = [:]
        for hit in fts where bestFTSRank[hit.pageID] == nil {
            bestFTSRank[hit.pageID] = hit.rank
        }

        var fused: [String: Double] = [:]
        for (page, rank) in bestKNNRank {
            fused[page, default: 0] += 1.0 / (rrfK + Double(rank))
        }
        for (page, rank) in bestFTSRank {
            fused[page, default: 0] += 1.0 / (rrfK + Double(rank))
        }
        return fused
    }

    // MARK: - Graph expansion

    static func expandGraph(_ db: Database, seeds: [String]) throws -> [String: Int] {
        guard !seeds.isEmpty else { return [:] }
        let placeholders = seeds.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            WITH RECURSIVE reachable(page_id, depth) AS (
                SELECT id, 0 FROM pages WHERE id IN (\(placeholders))
                UNION
                SELECT CASE WHEN e.src_page_id = r.page_id THEN e.dst_page_id
                            ELSE e.src_page_id END,
                       r.depth + 1
                FROM edges e JOIN reachable r
                    ON (e.src_page_id = r.page_id OR e.dst_page_id = r.page_id)
                WHERE r.depth < \(maxHops) AND e.dst_page_id IS NOT NULL
            )
            SELECT page_id, MIN(depth) AS hops
            FROM reachable
            WHERE page_id IS NOT NULL
            GROUP BY page_id;
        """
        var out: [String: Int] = [:]
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(seeds))
        for row in rows {
            out[row["page_id"]] = row["hops"]
        }
        return out
    }

    // MARK: - Helpers

    struct PageInfo {
        let title: String
        let summary: String?
        let updatedAt: Date?
    }

    static func fetchPageInfo(_ db: Database, pageIDs: [String]) throws -> [String: PageInfo] {
        guard !pageIDs.isEmpty else { return [:] }
        let placeholders = pageIDs.map { _ in "?" }.joined(separator: ", ")
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT id, title, summary, updated_at FROM pages WHERE id IN (\(placeholders));",
            arguments: StatementArguments(pageIDs)
        )
        var out: [String: PageInfo] = [:]
        for row in rows {
            out[row["id"]] = PageInfo(
                title: row["title"],
                summary: row["summary"],
                updatedAt: row["updated_at"]
            )
        }
        return out
    }

    static func fetchConnectionCounts(
        _ db: Database,
        candidates: [String],
        seeds: [String]
    ) throws -> [String: Int] {
        guard !candidates.isEmpty, !seeds.isEmpty else { return [:] }
        let candPH = candidates.map { _ in "?" }.joined(separator: ", ")
        let seedPH = seeds.map { _ in "?" }.joined(separator: ", ")

        // Argument order tracks the placeholders left-to-right:
        //   seedPH (src IN seeds) → candPH (dst IN candidates) →
        //   seedPH (dst IN seeds) → candPH (src IN candidates).
        let args = StatementArguments(seeds + candidates + seeds + candidates)
        let rows = try Row.fetchAll(db, sql: """
            SELECT page_id, COUNT(*) AS c FROM (
                SELECT dst_page_id AS page_id FROM edges
                WHERE src_page_id IN (\(seedPH)) AND dst_page_id IN (\(candPH))
                UNION ALL
                SELECT src_page_id AS page_id FROM edges
                WHERE dst_page_id IN (\(seedPH)) AND src_page_id IN (\(candPH))
            )
            GROUP BY page_id;
        """, arguments: args)
        var out: [String: Int] = [:]
        for row in rows {
            out[row["page_id"]] = row["c"]
        }
        return out
    }

    static func buildSeedSnippets(knn: [Hit], fts: [Hit]) -> [String: Hit] {
        var out: [String: Hit] = [:]
        // KNN first — semantic match is the better default snippet.
        for hit in knn where out[hit.pageID] == nil {
            out[hit.pageID] = hit
        }
        for hit in fts where out[hit.pageID] == nil {
            out[hit.pageID] = hit
        }
        return out
    }

    static func bestSimilarities(knn: [Hit]) -> [String: Double] {
        var out: [String: Double] = [:]
        for hit in knn {
            // Crude monotone normalisation: small distance → high score.
            let s = 1.0 / (1.0 + hit.metric)
            if (out[hit.pageID] ?? -.infinity) < s {
                out[hit.pageID] = s
            }
        }
        return out
    }

    /// Adaptive threshold derived from the returned KNN similarities:
    /// `median + 30 % of (best − median)`. A page beats the noise floor
    /// only when its similarity sits clearly above the bulk — i.e.
    /// when vec0 is actually telling us something. Returns 1.0 (an
    /// always-failing threshold) when the distribution is uniform
    /// (all sims equal), so noise queries don't seed any KNN page.
    static func noiseFloor(similarities: [String: Double]) -> Double {
        let sorted = similarities.values.sorted()
        guard let best = sorted.last, let worst = sorted.first else { return 1.0 }
        let median = sorted[sorted.count / 2]
        let spread = best - median
        // Avoid a meaningless threshold when the whole distribution is
        // flat — that's the signature of a query with no semantic
        // match.
        if spread < 1e-6 || (best - worst) < 1e-6 { return 1.0 }
        return median + 0.3 * spread
    }

    /// Best (lowest) BM25 rank per page across the FTS hit list. Used to
    /// give the final score a lexical push on top of the seed selection.
    static func bestRanksByPage(fts: [Hit]) -> [String: Int] {
        var out: [String: Int] = [:]
        for hit in fts {
            if (out[hit.pageID] ?? Int.max) > hit.rank {
                out[hit.pageID] = hit.rank
            }
        }
        return out
    }

    /// Half-life ~30 days. Plenty for a personal wiki — pages that
    /// haven't been touched in months drop, but anything touched in
    /// the last week wins a clear boost.
    static func recencyScore(updatedAt: Date?, reference: Date) -> Double {
        guard let updatedAt else { return 0 }
        let days = max(0, reference.timeIntervalSince(updatedAt) / 86_400)
        return exp(-days / 30.0)
    }

    /// Decodes `chunks.heading_path` (JSON array) into Swift strings.
    static func decodeHeadingPath(_ raw: String?) -> [String]? {
        guard let raw,
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return nil }
        return arr.isEmpty ? nil : arr
    }

    /// Keeps snippets bounded so a search result doesn't blow the
    /// agent's context budget.
    static func truncate(_ text: String, max: Int = 240) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…"
    }
}
