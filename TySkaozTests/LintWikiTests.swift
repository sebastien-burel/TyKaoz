import Foundation
import Testing
import GRDB
@testable import TySkaoz

@Suite
struct LintWikiTests {

    private static func makeContext() async throws -> (WikiContext, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LintWikiTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeRoot = tempDir.appendingPathComponent("wiki-store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let pool = try WikiDatabase.open(
            at: storeRoot.appendingPathComponent("index.sqlite"),
            embeddingDimension: 64
        )
        let ctx = WikiContext(
            storeRoot: storeRoot,
            pool: pool,
            embedder: FakeEmbeddingProvider(dimension: 64)
        )
        try ctx.bootstrapDirectoriesIfNeeded()
        return (ctx, tempDir)
    }

    private static func write(in dir: URL, _ name: String, _ content: String) throws {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test
    func emptyWikiHasNoIssues() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let report = try await ctx.pool.read { db in try Lint.run(db) }
        #expect(report.orphans.isEmpty)
        #expect(report.danglingLinks.isEmpty)
        #expect(report.missingConcepts.isEmpty)
    }

    @Test
    func detectsOrphanPage() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        // Two pages, no links between them — both orphans.
        try Self.write(in: ctx.wikiRoot, "a.md", "---\nid: a\ntitle: A\n---\nbody")
        try Self.write(in: ctx.wikiRoot, "b.md", "---\nid: b\ntitle: B\n---\nbody")
        _ = try await ctx.makeIndexer().reindexAll()

        let report = try await ctx.pool.read { db in try Lint.run(db) }
        #expect(report.orphans.map(\.pageID).sorted() == ["a", "b"])
    }

    @Test
    func incomingEdgeUnmarksOrphan() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Self.write(in: ctx.wikiRoot, "a.md",
            "---\nid: a\ntitle: A\n---\nVoir [[B]].")
        try Self.write(in: ctx.wikiRoot, "b.md",
            "---\nid: b\ntitle: B\n---\nbody")
        _ = try await ctx.makeIndexer().reindexAll()

        let report = try await ctx.pool.read { db in try Lint.run(db) }
        // A has no incoming → orphan. B has A→B → not orphan.
        #expect(report.orphans.map(\.pageID) == ["a"])
    }

    @Test
    func detectsDanglingLinks() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Self.write(in: ctx.wikiRoot, "a.md",
            "---\nid: a\ntitle: A\n---\nVoir [[Inconnue]] et [[Phantom]].")
        _ = try await ctx.makeIndexer().reindexAll()

        let report = try await ctx.pool.read { db in try Lint.run(db) }
        let titles = report.danglingLinks.map(\.dstTitleRaw).sorted()
        #expect(titles == ["Inconnue", "Phantom"])
    }

    @Test
    func detectsRecurringMissingConcepts() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        // Three pages mentioning "RAG" but no page titled RAG.
        try Self.write(in: ctx.wikiRoot, "a.md",
            "---\nid: a\ntitle: A\n---\nVoir [[RAG]].")
        try Self.write(in: ctx.wikiRoot, "b.md",
            "---\nid: b\ntitle: B\n---\nCf [[RAG]] aussi.")
        try Self.write(in: ctx.wikiRoot, "c.md",
            "---\nid: c\ntitle: C\n---\nEt [[Singleton]] (1 seul).")
        _ = try await ctx.makeIndexer().reindexAll()

        let report = try await ctx.pool.read { db in try Lint.run(db) }
        // Only "RAG" appears ≥2 times.
        #expect(report.missingConcepts.map(\.titleRaw) == ["RAG"])
        #expect(report.missingConcepts.first?.references == 2)
    }

    // MARK: - Tool surface

    @Test
    func lintWikiToolRendersMarkdownSections() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Self.write(in: ctx.wikiRoot, "a.md",
            "---\nid: a\ntitle: A\n---\nVoir [[Phantom]].")
        _ = try await ctx.makeIndexer().reindexAll()

        let tool = LintWikiTool(context: ctx)
        let out = try await tool.execute(arguments: Data("{}".utf8))
        #expect(out.contains("## Orphelins"))
        #expect(out.contains("## Liens pendouillants"))
        #expect(out.contains("Phantom"))
    }

    @Test
    func lintWikiToolAllClearCorpus() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Self.write(in: ctx.wikiRoot, "a.md",
            "---\nid: a\ntitle: A\n---\nVoir [[B]].")
        try Self.write(in: ctx.wikiRoot, "b.md",
            "---\nid: b\ntitle: B\n---\nCf [[A]].")
        _ = try await ctx.makeIndexer().reindexAll()

        let tool = LintWikiTool(context: ctx)
        let out = try await tool.execute(arguments: Data("{}".utf8))
        // Both pages link to each other → no orphans, no dangling.
        #expect(out.contains("## Orphelins\nAucun"))
        #expect(out.contains("## Liens pendouillants\nAucun"))
    }
}
