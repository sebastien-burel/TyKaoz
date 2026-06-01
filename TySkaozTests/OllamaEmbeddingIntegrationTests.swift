import Foundation
import Testing
import GRDB
@testable import TySkaoz

/// Real Ollama integration tests. Skipped automatically when Ollama
/// isn't reachable at the configured URL or when the required models
/// aren't pulled. Override the base URL via the `TYKAOZ_OLLAMA_URL`
/// environment variable (default `http://localhost:11434`).
///
/// What we're proving here, that no mock can: a real bge-m3 round-trip
/// — `/api/embed` returns 1024-dim Float32 vectors, sqlite-vec ingests
/// them, KNN against a fresh query embed retrieves the right chunk.
@Suite(.serialized)
struct OllamaEmbeddingIntegrationTests {

    static let baseURL: URL = {
        let raw = ProcessInfo.processInfo.environment["TYKAOZ_OLLAMA_URL"]
            ?? "http://localhost:11434"
        return URL(string: raw)!
    }()
    static let model = "bge-m3"
    static let dimension = 1024

    @Test
    func bgeM3ReturnsExpectedDimension() async throws {
        guard try await Self.isReachable() else {
            print("Ollama not reachable at \(Self.baseURL.absoluteString), skipping")
            return
        }
        guard try await Self.hasModel(Self.model) else {
            print("Model '\(Self.model)' not pulled on this Ollama, skipping")
            return
        }

        let client = OllamaClient(baseURL: Self.baseURL)
        let vectors = try await client.embed(
            model: Self.model,
            inputs: ["Bonjour le monde", "Phase 5 embeddings"]
        )
        #expect(vectors.count == 2)
        #expect(vectors[0].count == Self.dimension)
        #expect(vectors[1].count == Self.dimension)
        // Two different sentences should give two different vectors.
        #expect(vectors[0] != vectors[1])
        // And vectors shouldn't be all-zero.
        #expect(vectors[0].contains { $0 != 0 })
    }

    @Test
    func endToEndIndexAndKNNWithBgeM3() async throws {
        guard try await Self.isReachable() else {
            print("Ollama not reachable at \(Self.baseURL.absoluteString), skipping")
            return
        }
        guard try await Self.hasModel(Self.model) else {
            print("Model '\(Self.model)' not pulled on this Ollama, skipping")
            return
        }

        let (wikiURL, pool, tempDir) = try Self.makeFixture(dimension: Self.dimension)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Self.writePage(in: wikiURL, "ollama.md", content: """
        ---
        id: ollama
        title: Ollama
        ---

        # Ollama
        Serveur local pour modèles LLM open weights.

        # Embeddings
        bge-m3 produit des vecteurs de dimension 1024.
        """)
        try Self.writePage(in: wikiURL, "kayak.md", content: """
        ---
        id: kayak
        title: Kayak
        ---

        # Kayak
        Embarcation longue et fine, à pagaie double.
        """)

        let embedder = OllamaEmbeddingProvider(
            baseURL: Self.baseURL,
            modelID: Self.model,
            dimension: Self.dimension
        )
        let report = try await Indexer(wikiRoot: wikiURL, pool: pool, embedder: embedder)
            .reindexAll()
        #expect(report.added == 2)

        // Sanity: vec_chunks now holds vectors for every chunk.
        let counts = try await pool.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT count(*) FROM chunks;") ?? -1,
                try Int.fetchOne(db, sql: "SELECT count(*) FROM vec_chunks;") ?? -1
            )
        }
        #expect(counts.0 > 0)
        #expect(counts.0 == counts.1)

        // KNN with a query about ollama embeddings should land on a chunk
        // from the ollama page, not the kayak page.
        let query = try await embedder.embed(["embeddings dimension bge-m3"])[0]
        let queryBlob = query.withUnsafeBufferPointer { Data(buffer: $0) }
        // vec0 requires LIMIT to live inside the MATCH subquery — once
        // joined, the planner can't push the bound back down.
        let topPageID: String? = try await pool.read { db in
            try String.fetchOne(db, sql: """
                SELECT c.page_id
                FROM (
                    SELECT chunk_id FROM vec_chunks
                    WHERE embedding MATCH ?
                    ORDER BY distance LIMIT 1
                ) v
                JOIN chunks c ON c.id = v.chunk_id;
            """, arguments: [queryBlob])
        }
        #expect(topPageID == "ollama")
    }

    // MARK: - Helpers

    private static func isReachable() async throws -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "/api/tags"))
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    private static func hasModel(_ name: String) async throws -> Bool {
        let models = try await OllamaClient(baseURL: baseURL).listModels()
        return models.contains { $0.name.hasPrefix(name) }
    }

    private static func makeFixture(dimension: Int) throws -> (wiki: URL, db: DatabasePool, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OllamaEmbedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let wiki = tempDir.appendingPathComponent("wiki", isDirectory: true)
        try FileManager.default.createDirectory(at: wiki, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("index.sqlite")
        let pool = try WikiDatabase.open(at: dbURL, embeddingDimension: dimension)
        return (wiki, pool, tempDir)
    }

    private static func writePage(in wiki: URL, _ name: String, content: String) throws {
        let url = wiki.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
