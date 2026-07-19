import Foundation
import TyKaozKit
import GRDB
import CSqliteVec

/// Opens (or creates) the wiki knowledge graph database at the given URL.
/// Registers `sqlite-vec` as a SQLite auto-extension on the first call so
/// every connection in the pool inherits the `vec0` virtual table support.
///
/// The DB is a `DatabasePool` (one writer, many readers) because the
/// indexer writes from a background queue while the UI / agent read in
/// parallel. Migrations apply the v1 schema at open time.
enum WikiDatabase {
    static func open(
        at url: URL,
        embeddingDimension: Int = WikiSchemaV1.defaultEmbeddingDimension
    ) throws -> DatabasePool {
        var config = Configuration()
        config.prepareDatabase { db in
            // Initialise sqlite-vec on every connection in the pool. Done
            // here (rather than via sqlite3_auto_extension) so it works
            // regardless of which sqlite3 build GRDB ends up linking
            // against in the test bundle vs the app.
            let rc = csqlitevec_init_on_connection(db.sqliteConnection)
            if rc != SQLITE_OK {
                throw DatabaseError(resultCode: ResultCode(rawValue: rc))
            }
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        try migrator(embeddingDimension: embeddingDimension).migrate(pool)
        return pool
    }

    private static func migrator(embeddingDimension: Int) -> DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1.initial-schema") { db in
            try WikiSchemaV1.create(in: db, embeddingDimension: embeddingDimension)
        }
        return m
    }
}
