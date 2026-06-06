import Foundation
import Testing
import GRDB
@testable import TyKaoz

@Suite @MainActor
struct WikiFileWatcherTests {

    private static func makeContext() async throws -> (WikiContext, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WikiFileWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeRoot = tempDir.appendingPathComponent("wiki-store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let pool = try WikiDatabase.open(
            at: storeRoot.appendingPathComponent("index.sqlite"),
            embeddingDimension: 64
        )
        let embedder = FakeEmbeddingProvider(dimension: 64)
        let ctx = WikiContext(storeRoot: storeRoot, pool: pool, embedder: embedder)
        try ctx.bootstrapDirectoriesIfNeeded()
        return (ctx, tempDir)
    }

    @Test
    func notifyTriggersReindex() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Drop a page on disk.
        let pageURL = ctx.wikiRoot.appendingPathComponent("p1.md")
        try "---\nid: p1\ntitle: P1\n---\nhello".write(
            to: pageURL, atomically: true, encoding: .utf8
        )

        let watcher = WikiFileWatcher(context: ctx, debounceMs: 30)
        watcher.notify()
        await watcher.waitForSettled()

        let count = try await ctx.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM pages;") ?? -1
        }
        #expect(count == 1)
        #expect(watcher.lastIndexReport?.added == 1)
    }

    @Test
    func burstOfNotifiesCoalescesIntoOneReindex() async throws {
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "---\nid: p1\ntitle: P1\n---\nhello".write(
            to: ctx.wikiRoot.appendingPathComponent("p1.md"),
            atomically: true,
            encoding: .utf8
        )

        let watcher = WikiFileWatcher(context: ctx, debounceMs: 50)
        // 5 rapid notifies — only the last should actually reindex.
        for _ in 0..<5 {
            watcher.notify()
            try? await Task.sleep(for: .milliseconds(5))
        }
        await watcher.waitForSettled()

        // Single reindex → one .added (p1 was new).
        #expect(watcher.lastIndexReport?.added == 1)
    }

    /// End-to-end FSEvents validation. Skipped by default because
    /// FSEvents inside an xctest bundle running under app-sandbox
    /// doesn't reliably fire callbacks for the test container's
    /// temp directory. The debounce + reindex contract is covered
    /// by the `notify()` tests above; this one only proves the
    /// FSEvents wiring under a real (unsandboxed) host.
    ///
    /// Set TYKAOZ_RUN_FSEVENTS=1 in the test runner environment to
    /// opt back in when validating on a non-sandboxed test target.
    @Test
    func fsEventsTriggersReindexEndToEnd() async throws {
        guard ProcessInfo.processInfo.environment["TYKAOZ_RUN_FSEVENTS"] == "1" else {
            print("Skipping FSEvents E2E (set TYKAOZ_RUN_FSEVENTS=1 to enable)")
            return
        }
        let (ctx, tempDir) = try await Self.makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let watcher = WikiFileWatcher(context: ctx, debounceMs: 50)
        try watcher.start()
        defer { watcher.stop() }

        try "---\nid: p1\ntitle: P1\n---\nbody".write(
            to: ctx.wikiRoot.appendingPathComponent("p1.md"),
            atomically: true,
            encoding: .utf8
        )
        var observed = 0
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(50))
            observed = try await ctx.pool.read { db in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM pages;") ?? -1
            }
            if observed == 1 { break }
        }
        #expect(observed == 1)
    }
}
