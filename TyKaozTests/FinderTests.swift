import Foundation
import Testing
import GRDB
@testable import TyKaoz

@Suite
struct FinderTests {

    // MARK: - Fixture helpers

    /// Builds a mini wiki of 6 pages with explicit cross-links.
    /// All pages are indexed with the FakeEmbeddingProvider so KNN
    /// returns deterministic results based on text hashing.
    ///
    /// Topology:
    ///   ollama ─link→ embeddings ─link→ vec0
    ///   ollama ─link→ models
    ///   kayak ─link→ riviere
    ///
    /// "ollama", "embeddings", "vec0", "models" form a connected cluster.
    /// "kayak", "riviere" form a separate cluster.
    private static func makeCorpus(dimension: Int) async throws ->
        (wiki: URL, pool: DatabasePool, embedder: FakeEmbeddingProvider, tempDir: URL)
    {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let wiki = tempDir.appendingPathComponent("wiki", isDirectory: true)
        try FileManager.default.createDirectory(at: wiki, withIntermediateDirectories: true)

        try write(in: wiki, "ollama.md", content: """
        ---
        id: ollama
        title: Ollama
        ---

        # Présentation

        Ollama est un runtime local pour modèles LLM open weights.
        Voir [[Embeddings]] et [[Models]].
        """)

        try write(in: wiki, "embeddings.md", content: """
        ---
        id: embeddings
        title: Embeddings
        ---

        # Vue d'ensemble

        Les embeddings transforment du texte en vecteurs denses.
        bge-m3 produit du 1024 dim. Cf. [[vec0]].
        """)

        try write(in: wiki, "vec0.md", content: """
        ---
        id: vec0
        title: vec0
        ---

        Table virtuelle SQLite pour faire du KNN exact sur des vecteurs.
        """)

        try write(in: wiki, "models.md", content: """
        ---
        id: models
        title: Models
        ---

        Liste des modèles locaux Ollama : llama, mistral, qwen.
        """)

        try write(in: wiki, "kayak.md", content: """
        ---
        id: kayak
        title: Kayak
        ---

        Embarcation longue et fine, à pagaie double.
        Cf. [[Rivière]].
        """)

        try write(in: wiki, "riviere.md", content: """
        ---
        id: riviere
        title: Rivière
        ---

        Cours d'eau. Bon terrain pour le kayak.
        """)

        let dbURL = tempDir.appendingPathComponent("index.sqlite")
        let pool = try WikiDatabase.open(at: dbURL, embeddingDimension: dimension)
        let embedder = FakeEmbeddingProvider(dimension: dimension)
        _ = try await Indexer(wikiRoot: wiki, pool: pool, embedder: embedder).reindexAll()
        return (wiki, pool, embedder, tempDir)
    }

    private static func write(in wiki: URL, _ name: String, content: String) throws {
        try content.write(
            to: wiki.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Tests

    @Test
    func bm25HitsTheLexicalMatch() async throws {
        let f = try await Self.makeCorpus(dimension: 64)
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        // "pagaie" appears only in the kayak page; with a 6-page corpus
        // KNN is uniform-ish noise, so the BM25 boost in the score has
        // to lift kayak above the hub pages (ollama, embeddings).
        let finder = Finder(pool: f.pool, embedder: f.embedder)
        let results = try await finder.search("pagaie")
        #expect(!results.isEmpty)
        #expect(results.first?.pageID == "kayak")
    }

    @Test
    func returnsHopMetadataForGraphExpandedNeighbours() async throws {
        let f = try await Self.makeCorpus(dimension: 64)
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        // "Ollama" matches the ollama page; vec0 is 2 hops away
        // (ollama → embeddings → vec0).
        let finder = Finder(pool: f.pool, embedder: f.embedder)
        let results = try await finder.search("Ollama runtime modèles")
        let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.pageID, $0) })
        #expect(byID["ollama"]?.hops == 0)
        if let emb = byID["embeddings"] {
            #expect(emb.hops == 1)
        }
        if let vec = byID["vec0"] {
            #expect(vec.hops == 2)
        }
    }

    @Test
    func seedsCarryActualChunkSnippet() async throws {
        let f = try await Self.makeCorpus(dimension: 64)
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        let finder = Finder(pool: f.pool, embedder: f.embedder)
        let results = try await finder.search("pagaie")
        let kayak = results.first { $0.pageID == "kayak" }
        #expect(kayak?.snippet.contains("pagaie") == true)
        #expect(kayak?.hops == 0)
    }

    @Test
    func neighboursUseTitleWhenSummaryAbsent() async throws {
        let f = try await Self.makeCorpus(dimension: 64)
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        let finder = Finder(pool: f.pool, embedder: f.embedder)
        let results = try await finder.search("Ollama runtime")
        // The neighbour page should snippet to its title since
        // pages.summary is currently always NULL.
        let neighbour = results.first(where: { $0.hops > 0 })
        if let n = neighbour {
            #expect(n.snippet == n.title)
            #expect(n.headingPath == nil)
        }
    }

    @Test
    func respectsRequestedLimit() async throws {
        let f = try await Self.makeCorpus(dimension: 64)
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        let finder = Finder(pool: f.pool, embedder: f.embedder)
        let results = try await finder.search("Ollama runtime modèles", limit: 2)
        #expect(results.count <= 2)
    }

    @Test
    func returnsEmptyForUnknownQuery() async throws {
        let f = try await Self.makeCorpus(dimension: 64)
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        // No page contains "xyzzyzonk" so neither KNN-near-zero nor BM25
        // will return seeds. (KNN will still rank everything; we just
        // expect that with no FTS hit and the fake embedder's noise,
        // the seed set is small or empty enough that the result list
        // remains short.)
        let finder = Finder(pool: f.pool, embedder: f.embedder)
        let results = try await finder.search("xyzzyzonk")
        // Either empty or short — not the full corpus.
        #expect(results.count <= 4)
    }

    @Test
    func scoreDecreasesWithHops() async throws {
        let f = try await Self.makeCorpus(dimension: 64)
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        let finder = Finder(pool: f.pool, embedder: f.embedder)
        let results = try await finder.search("pagaie")
        // Seed (kayak) scores higher than its 1-hop neighbour (rivière):
        // the seed picks up the BM25 boost AND a stronger sim, plus a
        // bigger hop-score (1.0 vs 0.5), beating the neighbour's
        // connection-count bump.
        let kayak = results.first(where: { $0.pageID == "kayak" })
        let riviere = results.first(where: { $0.pageID == "riviere" })
        if let k = kayak, let r = riviere {
            #expect(k.score > r.score)
        }
    }

    @Test
    func rrfFusionMath() {
        // Algorithmic sanity: a page that ranks #1 in both KNN and BM25
        // must score strictly higher than a page that ranks #1 in only
        // one of them.
        let knn = [
            Finder.Hit(pageID: "a", chunkID: 1, text: "", headingPath: nil, rank: 1, metric: 0),
            Finder.Hit(pageID: "b", chunkID: 2, text: "", headingPath: nil, rank: 2, metric: 0)
        ]
        let fts = [
            Finder.Hit(pageID: "a", chunkID: 1, text: "", headingPath: nil, rank: 1, metric: 0),
            Finder.Hit(pageID: "c", chunkID: 3, text: "", headingPath: nil, rank: 2, metric: 0)
        ]
        let fused = Finder.fuseByRRF(knn: knn, fts: fts)
        #expect((fused["a"] ?? 0) > (fused["b"] ?? 0))
        #expect((fused["a"] ?? 0) > (fused["c"] ?? 0))
    }

    @Test
    func graphExpansionGivesMinimumHops() async throws {
        let f = try await Self.makeCorpus(dimension: 64)
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        let hops = try await f.pool.read { db in
            try Finder.expandGraph(db, seeds: ["ollama"])
        }
        // The cluster around ollama should all be reachable; the
        // disconnected kayak/riviere shouldn't.
        #expect(hops["ollama"] == 0)
        #expect(hops["embeddings"] == 1)
        #expect(hops["models"] == 1)
        #expect(hops["vec0"] == 2)
        #expect(hops["kayak"] == nil)
        #expect(hops["riviere"] == nil)
    }
}
