import Foundation
import GRDB

/// First migration — the schema defined in PLAN_TYKAOZ_WIKI.md.
/// Markdown on disk stays canonical; this database is a derived index.
enum WikiSchemaV1 {
    /// Dimension of the embedding vectors. Locked once the column is
    /// created; changing models requires a "rebuild vectoriel" migration
    /// that drops and re-creates `vec_chunks` only.
    static let embeddingDimension = 768

    static func create(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE pages (
                id           TEXT PRIMARY KEY,
                path         TEXT NOT NULL UNIQUE,
                title        TEXT NOT NULL,
                type         TEXT,
                summary      TEXT,
                content_hash TEXT NOT NULL,
                updated_at   DATETIME,
                created_at   DATETIME
            );
        """)

        try db.execute(sql: """
            CREATE TABLE edges (
                src_page_id   TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
                dst_page_id   TEXT REFERENCES pages(id) ON DELETE CASCADE,
                dst_title_raw TEXT NOT NULL,
                rel_type      TEXT NOT NULL DEFAULT 'link',
                PRIMARY KEY (src_page_id, dst_title_raw, rel_type)
            );
        """)
        try db.execute(sql: "CREATE INDEX idx_edges_dst ON edges(dst_page_id);")

        try db.execute(sql: """
            CREATE TABLE chunks (
                id           INTEGER PRIMARY KEY,
                page_id      TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
                ordinal      INTEGER NOT NULL,
                heading_path TEXT,
                text         TEXT NOT NULL
            );
        """)
        try db.execute(sql: "CREATE INDEX idx_chunks_page ON chunks(page_id);")

        try db.execute(sql: """
            CREATE VIRTUAL TABLE vec_chunks USING vec0(
                chunk_id  INTEGER PRIMARY KEY,
                embedding FLOAT[\(embeddingDimension)]
            );
        """)

        try db.execute(sql: """
            CREATE VIRTUAL TABLE fts_chunks USING fts5(
                text,
                content='chunks',
                content_rowid='id'
            );
        """)

        try db.execute(sql: """
            CREATE TABLE sources (
                id          TEXT PRIMARY KEY,
                path        TEXT NOT NULL,
                kind        TEXT,
                hash        TEXT NOT NULL,
                ingested_at DATETIME
            );
        """)
        try db.execute(sql: """
            CREATE TABLE page_sources (
                page_id   TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
                source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
                PRIMARY KEY (page_id, source_id)
            );
        """)
    }
}
