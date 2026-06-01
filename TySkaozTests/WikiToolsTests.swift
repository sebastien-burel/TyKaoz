import Foundation
import Testing
import GRDB
@testable import TySkaoz

@Suite
struct WikiToolsTests {

    // MARK: - Fixture

    /// Spins up a wiki store with the same 6-page corpus FinderTests
    /// uses, indexed via the BoW fake embedder. Returns a `WikiContext`
    /// the tools can plug into.
    private static func makeContext() async throws -> (WikiContext, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WikiToolsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeRoot = tempDir.appendingPathComponent("wiki-store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let embedder = FakeEmbeddingProvider(dimension: 64)
        let pool = try WikiDatabase.open(
            at: storeRoot.appendingPathComponent("index.sqlite"),
            embeddingDimension: 64
        )
        let context = WikiContext(storeRoot: storeRoot, pool: pool, embedder: embedder)
        try context.bootstrapDirectoriesIfNeeded()

        try write(in: context.wikiRoot, "ollama.md", """
        ---
        id: ollama
        title: Ollama
        ---

        # Présentation
        Ollama est un runtime local pour modèles LLM open weights.
        Voir [[Embeddings]].
        """)
        try write(in: context.wikiRoot, "embeddings.md", """
        ---
        id: embeddings
        title: Embeddings
        ---

        # Vue d'ensemble
        Les embeddings transforment du texte en vecteurs denses.
        bge-m3 produit du 1024 dim.
        """)
        try write(in: context.wikiRoot, "kayak.md", """
        ---
        id: kayak
        title: Kayak
        ---

        Embarcation longue et fine, à pagaie double.
        """)

        _ = try await context.makeIndexer().reindexAll()
        return (context, tempDir)
    }

    private static func write(in wiki: URL, _ name: String, _ content: String) throws {
        try content.write(
            to: wiki.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - SearchWikiTool

    @Test
    func searchWikiReturnsMarkdownBlobForRelevantQuery() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SearchWikiTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: ["query": "pagaie"])
        let out = try await tool.execute(arguments: args)
        #expect(out.contains("Kayak"))
        #expect(out.contains("match direct"))
        #expect(out.contains("kayak"))  // page id
    }

    @Test
    func searchWikiReportsEmptyForNoMatch() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SearchWikiTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: ["query": "xyzzyzonk"])
        let out = try await tool.execute(arguments: args)
        #expect(out.contains("Aucun résultat"))
    }

    @Test
    func searchWikiRequiresQueryArg() async {
        let tool = SearchWikiTool(context: try! await Self.makeContext().0)
        let args = try! JSONSerialization.data(withJSONObject: [:] as [String: Any])
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: args)
        }
    }

    @Test
    func searchWikiNeedsEmbedder() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Same store but no embedder → tool should refuse cleanly.
        let bare = WikiContext(storeRoot: ctx.storeRoot, pool: ctx.pool, embedder: nil)
        let tool = SearchWikiTool(context: bare)
        let args = try JSONSerialization.data(withJSONObject: ["query": "anything"])
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: args)
        }
    }

    // MARK: - ReadPageTool

    @Test
    func readPageByID() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ReadPageTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: ["id": "kayak"])
        let out = try await tool.execute(arguments: args)
        #expect(out.contains("--- id: kayak"))
        #expect(out.contains("--- path: kayak.md"))
        #expect(out.contains("--- hash:"))
        #expect(out.contains("pagaie"))  // body content
    }

    @Test
    func readPageByTitle() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ReadPageTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: ["title": "Embeddings"])
        let out = try await tool.execute(arguments: args)
        #expect(out.contains("--- id: embeddings"))
        #expect(out.contains("bge-m3"))
    }

    @Test
    func readPageMissingThrows() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ReadPageTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: ["id": "no-such-page"])
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: args)
        }
    }

    @Test
    func readPageRequiresIdOrTitle() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ReadPageTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: args)
        }
    }
}
