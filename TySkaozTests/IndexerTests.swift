import Foundation
import Testing
import GRDB
@testable import TySkaoz

@Suite
struct IndexerTests {

    // MARK: - Fixtures

    /// Sets up a fresh wiki/ directory + SQLite pool. Caller is
    /// responsible for cleanup (rm -rf the temp dir).
    private static func makeFixture() throws -> (wiki: URL, db: DatabasePool, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let wiki = tempDir.appendingPathComponent("wiki", isDirectory: true)
        try FileManager.default.createDirectory(at: wiki, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("index.sqlite")
        let pool = try WikiDatabase.open(at: dbURL)
        return (wiki, pool, tempDir)
    }

    private static func writePage(_ name: String, content: String, in wiki: URL) throws {
        let url = wiki.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Tests

    @Test
    func indexesEmptyDirectoryAsNoOp() async throws {
        let f = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        let indexer = Indexer(wikiRoot: f.wiki, pool: f.db)
        let report = try await indexer.reindexAll()
        #expect(report.added == 0)
        #expect(report.updated == 0)
        #expect(report.removed == 0)
    }

    @Test
    func indexesSinglePage() async throws {
        let f = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        try Self.writePage("phase-6.md", content: """
        ---
        id: phase-6
        title: Phase 6
        ---

        # Intro

        Voici Phase 6 et un lien vers [[Phase 5]].
        """, in: f.wiki)

        let report = try await Indexer(wikiRoot: f.wiki, pool: f.db).reindexAll()
        #expect(report.added == 1)

        let row: (id: String, title: String)? = try await f.db.read { db in
            try Row.fetchOne(db, sql: "SELECT id, title FROM pages WHERE id = 'phase-6';")
                .map { ($0["id"], $0["title"]) }
        }
        #expect(row?.id == "phase-6")
        #expect(row?.title == "Phase 6")

        let chunkCount = try await f.db.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM chunks WHERE page_id = 'phase-6';") ?? -1
        }
        #expect(chunkCount > 0)
    }

    @Test
    func resolvesWikilinksToKnownPages() async throws {
        let f = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        try Self.writePage("phase-5.md", content: """
        ---
        id: phase-5
        title: Phase 5
        ---

        Phase 5 content.
        """, in: f.wiki)
        try Self.writePage("phase-6.md", content: """
        ---
        id: phase-6
        title: Phase 6
        ---

        Voir [[Phase 5]] et [[Inconnue]].
        """, in: f.wiki)

        _ = try await Indexer(wikiRoot: f.wiki, pool: f.db).reindexAll()

        let edges: [(rawTitle: String, dstID: String?)] = try await f.db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT dst_title_raw, dst_page_id FROM edges WHERE src_page_id = 'phase-6';
            """).map { ($0["dst_title_raw"], $0["dst_page_id"]) }
        }
        #expect(edges.count == 2)
        let resolved = edges.first(where: { $0.rawTitle == "Phase 5" })
        #expect(resolved?.dstID == "phase-5")
        let unresolved = edges.first(where: { $0.rawTitle == "Inconnue" })
        #expect(unresolved?.dstID == nil)
    }

    @Test
    func skipsUnchangedPagesOnRescan() async throws {
        let f = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        try Self.writePage("p.md", content: "# Hello\n\nfirst.", in: f.wiki)
        let first = try await Indexer(wikiRoot: f.wiki, pool: f.db).reindexAll()
        #expect(first.added == 1)

        let second = try await Indexer(wikiRoot: f.wiki, pool: f.db).reindexAll()
        #expect(second.added == 0)
        #expect(second.updated == 0)
        #expect(second.unchanged == 1)
    }

    @Test
    func reindexesChangedPages() async throws {
        let f = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        try Self.writePage("p.md", content: """
        ---
        id: p
        title: P
        ---

        Avant.
        """, in: f.wiki)
        _ = try await Indexer(wikiRoot: f.wiki, pool: f.db).reindexAll()

        try Self.writePage("p.md", content: """
        ---
        id: p
        title: P
        ---

        Après.
        """, in: f.wiki)
        let second = try await Indexer(wikiRoot: f.wiki, pool: f.db).reindexAll()
        #expect(second.updated == 1)

        let chunkText: String? = try await f.db.read { db in
            try String.fetchOne(db, sql: "SELECT text FROM chunks WHERE page_id = 'p' LIMIT 1;")
        }
        #expect(chunkText == "Après.")
    }

    @Test
    func removesDeletedPages() async throws {
        let f = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        try Self.writePage("p1.md", content: "---\nid: p1\ntitle: P1\n---\nbody", in: f.wiki)
        try Self.writePage("p2.md", content: "---\nid: p2\ntitle: P2\n---\nbody", in: f.wiki)
        _ = try await Indexer(wikiRoot: f.wiki, pool: f.db).reindexAll()

        try FileManager.default.removeItem(at: f.wiki.appendingPathComponent("p2.md"))
        let report = try await Indexer(wikiRoot: f.wiki, pool: f.db).reindexAll()
        #expect(report.removed == 1)

        let remaining = try await f.db.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM pages ORDER BY id;")
        }
        #expect(remaining == ["p1"])
    }

    @Test
    func walksNestedSubdirectories() async throws {
        let f = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: f.tempDir) }

        try Self.writePage("notes/personal.md",
            content: "---\nid: n1\ntitle: Notes\n---\nbody",
            in: f.wiki)
        try Self.writePage("notes/projects/x.md",
            content: "---\nid: n2\ntitle: X\n---\nbody",
            in: f.wiki)

        let report = try await Indexer(wikiRoot: f.wiki, pool: f.db).reindexAll()
        #expect(report.added == 2)
    }
}
