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

    static func write(in dir: URL, _ name: String, _ content: String) throws {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
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

    // MARK: - ListSourcesTool

    @Test
    func listSourcesEnumeratesRawFiles() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Self.write(in: ctx.rawRoot, "conversations/abc.md", "# Conv 1\n\nHello.")
        try Self.write(in: ctx.rawRoot, "docs/note.txt", "Just a note.")

        let tool = ListSourcesTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        let out = try await tool.execute(arguments: args)
        #expect(out.contains("conversations/abc"))
        #expect(out.contains("docs/note"))
        #expect(out.contains("md"))
        #expect(out.contains("txt"))
    }

    @Test
    func listSourcesFiltersByKind() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Self.write(in: ctx.rawRoot, "a.md", "md")
        try Self.write(in: ctx.rawRoot, "b.txt", "txt")

        let tool = ListSourcesTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: ["kind": "txt"])
        let out = try await tool.execute(arguments: args)
        #expect(out.contains("b"))
        #expect(!out.contains("a (md"))
    }

    @Test
    func listSourcesReportsEmptyWhenRawMissing() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WikiToolsTests-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeRoot = tempDir.appendingPathComponent("wiki-store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let pool = try WikiDatabase.open(
            at: storeRoot.appendingPathComponent("index.sqlite"),
            embeddingDimension: 64
        )
        let ctx = WikiContext(storeRoot: storeRoot, pool: pool, embedder: nil)
        // Deliberately skip bootstrapDirectoriesIfNeeded() — raw/ doesn't exist.

        let tool = ListSourcesTool(context: ctx)
        let out = try await tool.execute(arguments: Data("{}".utf8))
        #expect(out.contains("n'existe pas"))
    }

    // MARK: - ReadSourceTool

    @Test
    func readSourceReturnsContent() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Self.write(in: ctx.rawRoot, "conversations/2026-06-01.md",
                       "# Conversation\n\nUser: bonjour")

        let tool = ReadSourceTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: ["id": "conversations/2026-06-01"])
        let out = try await tool.execute(arguments: args)
        #expect(out.contains("Conversation"))
        #expect(out.contains("bonjour"))
        #expect(out.contains("--- source: conversations/2026-06-01.md"))
    }

    @Test
    func readSourceRejectsBinaryKind() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Self.write(in: ctx.rawRoot, "doc.pdf", "%PDF-1.4 fake")

        let tool = ReadSourceTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: [
            "id": "doc", "kind": "pdf"
        ])
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: args)
        }
    }

    @Test
    func readSourceRejectsPathEscape() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ReadSourceTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: ["id": "../wiki/ollama"])
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: args)
        }
    }

    @Test
    func readSourceMissingThrows() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ReadSourceTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: ["id": "nope"])
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: args)
        }
    }

    // MARK: - WriteWikiPageTool

    @Test
    func writeCreatesNewPage() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = WriteWikiPageTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: [
            "path": "notes/new.md",
            "content": "---\nid: new\ntitle: New\n---\n\n# New\n\nFresh content."
        ])
        let out = try await tool.execute(arguments: args)
        #expect(out.contains("Écrit notes/new.md"))
        #expect(out.contains("hash:"))

        // File is on disk.
        let url = ctx.wikiRoot.appendingPathComponent("notes/new.md")
        #expect(FileManager.default.fileExists(atPath: url.path))

        // And indexed.
        let exists = try await ctx.pool.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM pages WHERE id = 'new');") ?? false
        }
        #expect(exists == true)
    }

    @Test
    func writeRejectsBadPath() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = WriteWikiPageTool(context: ctx)
        for badPath in ["../escape.md", "/abs/path.md", "no-extension", "notes/file.txt"] {
            let args = try JSONSerialization.data(withJSONObject: [
                "path": badPath, "content": "x"
            ])
            await #expect(throws: ToolError.self) {
                _ = try await tool.execute(arguments: args)
            }
        }
    }

    @Test
    func writeDetectsStaleHash() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = WriteWikiPageTool(context: ctx)
        // Overwriting an existing page (kayak) with a wrong expected_hash.
        let args = try JSONSerialization.data(withJSONObject: [
            "path": "kayak.md",
            "content": "---\nid: kayak\ntitle: Kayak\n---\nNew content.",
            "expected_hash": "0000000000000000000000000000000000000000000000000000000000000000"
        ])
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: args)
        }

        // File on disk unchanged (still mentions "pagaie" from the fixture).
        let url = ctx.wikiRoot.appendingPathComponent("kayak.md")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk.contains("pagaie"))
    }

    @Test
    func writeAcceptsCorrectExpectedHash() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Read current hash from disk.
        let url = ctx.wikiRoot.appendingPathComponent("kayak.md")
        let current = try String(contentsOf: url, encoding: .utf8)
        let hash = HashStore.sha256(current)

        let tool = WriteWikiPageTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: [
            "path": "kayak.md",
            "content": "---\nid: kayak\ntitle: Kayak\n---\nv2",
            "expected_hash": hash
        ])
        _ = try await tool.execute(arguments: args)

        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after.contains("v2"))
    }

    @Test
    func writeNormalizesWikilinks() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Fixture has a page titled "Ollama" with id "ollama".
        let tool = WriteWikiPageTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: [
            "path": "notes/related.md",
            "content": "---\nid: related\ntitle: Related\n---\n\nVoir [[Ollama]] et [[Inconnue]]."
        ])
        _ = try await tool.execute(arguments: args)

        let onDisk = try String(
            contentsOf: ctx.wikiRoot.appendingPathComponent("notes/related.md"),
            encoding: .utf8
        )
        #expect(onDisk.contains("[[ollama|Ollama]]"))
        #expect(onDisk.contains("[[Inconnue]]"))  // unresolved, stays bare
    }

    @Test
    func writeRefusesTitleCollisionOnNewPath() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // First write — creates the canonical "Le Sucre" page.
        let tool = WriteWikiPageTool(context: ctx)
        let first = try JSONSerialization.data(withJSONObject: [
            "path": "sucre.md",
            "content": "---\nid: sucre\ntitle: Le Sucre\n---\nv1"
        ])
        _ = try await tool.execute(arguments: first)

        // Second write — same title (case-insensitive), different path.
        let second = try JSONSerialization.data(withJSONObject: [
            "path": "le-sucre.md",
            "content": "---\nid: le-sucre\ntitle: le sucre\n---\nv2"
        ])
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: second)
        }

        // Only the original file is on disk; the duplicate path
        // never landed.
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: ctx.wikiRoot.appendingPathComponent("sucre.md").path))
        #expect(!fm.fileExists(atPath: ctx.wikiRoot.appendingPathComponent("le-sucre.md").path))
    }

    @Test
    func writeAllowsSameTitleOnSamePath() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Pre-seed.
        let url = ctx.wikiRoot.appendingPathComponent("sucre.md")
        let original = "---\nid: sucre\ntitle: Le Sucre\n---\nv1"
        try original.write(to: url, atomically: true, encoding: .utf8)
        let hash = HashStore.sha256(original)

        // Update on the SAME path with the SAME title — collision guard
        // must not fire here.
        let tool = WriteWikiPageTool(context: ctx)
        let update = try JSONSerialization.data(withJSONObject: [
            "path": "sucre.md",
            "content": "---\nid: sucre\ntitle: Le Sucre\n---\nv2 contenu enrichi",
            "expected_hash": hash
        ])
        _ = try await tool.execute(arguments: update)

        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk.contains("v2 contenu enrichi"))
    }

    @Test
    func writeStampsCreatedAndUpdatedDates() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = WriteWikiPageTool(context: ctx)
        // Agent writes a bogus year — tool should overwrite both fields.
        let args = try JSONSerialization.data(withJSONObject: [
            "path": "notes/dated.md",
            "content": """
            ---
            id: dated
            title: Dated
            created: 1999-01-01
            ---
            body
            """
        ])
        _ = try await tool.execute(arguments: args)

        let onDisk = try String(
            contentsOf: ctx.wikiRoot.appendingPathComponent("notes/dated.md"),
            encoding: .utf8
        )
        // The "1999-01-01" must be gone for a fresh page.
        #expect(!onDisk.contains("1999-01-01"))
        // Both fields stamped with today's ISO date.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let today = formatter.string(from: .now)
        #expect(onDisk.contains("created: \(today)"))
        #expect(onDisk.contains("updated: \(today)"))
    }

    @Test
    func writePreservesCreatedOnOverwrite() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Pre-seed a page with a real created date via the file system,
        // then read its hash for the CAS round-trip.
        let url = ctx.wikiRoot.appendingPathComponent("notes/preserved.md")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let firstWrite = """
        ---
        id: preserved
        title: Preserved
        created: 2025-01-15
        updated: 2025-01-15
        ---
        original body
        """
        try firstWrite.write(to: url, atomically: true, encoding: .utf8)
        let hash = HashStore.sha256(firstWrite)

        let tool = WriteWikiPageTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: [
            "path": "notes/preserved.md",
            "content": """
            ---
            id: preserved
            title: Preserved
            ---
            revised body
            """,
            "expected_hash": hash
        ])
        _ = try await tool.execute(arguments: args)

        let onDisk = try String(contentsOf: url, encoding: .utf8)
        // created kept from the previous version.
        #expect(onDisk.contains("created: 2025-01-15"))
        // updated bumped to today.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        #expect(onDisk.contains("updated: \(formatter.string(from: .now))"))
        #expect(onDisk.contains("revised body"))
    }

    @Test
    func writeReportsGitStatus() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = WriteWikiPageTool(context: ctx)
        let args = try JSONSerialization.data(withJSONObject: [
            "path": "notes/git-check.md",
            "content": "---\nid: git\ntitle: Git\n---\n\nbody"
        ])
        let out = try await tool.execute(arguments: args)
        // The test bundle inherits the app's sandbox, which blocks
        // launching /usr/bin/git from inside the container — so the
        // tool reports "indisponible" but still writes the file. The
        // contract is that the audit log is best-effort, never
        // load-bearing for the write itself.
        #expect(out.contains("git:"))
        #expect(out.contains("Écrit"))
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
