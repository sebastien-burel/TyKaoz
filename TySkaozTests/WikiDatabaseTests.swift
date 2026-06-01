import Foundation
import Testing
import GRDB
@testable import TySkaoz

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
}
