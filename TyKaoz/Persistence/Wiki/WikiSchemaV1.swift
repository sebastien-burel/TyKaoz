import Foundation
import GRDB

/// First migration — the schema defined in PLAN_TYKAOZ_WIKI.md.
/// Markdown on disk stays canonical; this database is a derived index.
enum WikiSchemaV1 {
    /// Default embedding dimension (nomic-embed-text). Locked once the
    /// column is created; changing models with a different dim requires
    /// the "rebuild vectoriel" migration that drops and re-creates
    /// `vec_chunks` only.
    static let defaultEmbeddingDimension = 768

    static func create(in db: Database, embeddingDimension: Int = defaultEmbeddingDimension) throws {
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
        // Persist the chosen dimension so future code paths (rebuild
        // vectoriel, migrations) can read it back without re-parsing the
        // vec0 declaration.
        try db.execute(sql: """
            CREATE TABLE wiki_meta (
                key   TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
        """)
        try db.execute(sql: """
            INSERT INTO wiki_meta (key, value) VALUES ('embedding_dimension', ?);
        """, arguments: [String(embeddingDimension)])

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

        // Virtual tables (vec0, fts5) can't participate in foreign-key
        // cascades. Hand-rolled triggers keep them in sync with `chunks`
        // so deleting a page propagates through chunks → vec_chunks /
        // fts_chunks without leaving orphan vectors or stale index entries.

        try db.execute(sql: """
            CREATE TRIGGER chunks_ai_fts AFTER INSERT ON chunks BEGIN
                INSERT INTO fts_chunks(rowid, text) VALUES (new.id, new.text);
            END;
        """)
        try db.execute(sql: """
            CREATE TRIGGER chunks_ad_fts AFTER DELETE ON chunks BEGIN
                INSERT INTO fts_chunks(fts_chunks, rowid, text)
                VALUES ('delete', old.id, old.text);
            END;
        """)
        try db.execute(sql: """
            CREATE TRIGGER chunks_au_fts AFTER UPDATE ON chunks BEGIN
                INSERT INTO fts_chunks(fts_chunks, rowid, text)
                VALUES ('delete', old.id, old.text);
                INSERT INTO fts_chunks(rowid, text) VALUES (new.id, new.text);
            END;
        """)

        try db.execute(sql: """
            CREATE TRIGGER chunks_ad_vec AFTER DELETE ON chunks BEGIN
                DELETE FROM vec_chunks WHERE chunk_id = old.id;
            END;
        """)
    }
}
