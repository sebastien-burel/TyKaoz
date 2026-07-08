import Foundation
import GRDB

/// Bundles every piece the wiki tools need: the on-disk store layout,
/// the SQLite index, and (when configured) the embedder. Constructed
/// once at app startup and threaded into each tool.
///
/// Layout per PLAN_TYKAOZ_WIKI.md:
///   storeRoot/
///   ├── raw/    immutable sources
///   └── wiki/   canonical markdown
struct WikiContext: Sendable {
    let storeRoot: URL
    let pool: DatabasePool
    let embedder: (any EmbeddingProvider)?

    init(storeRoot: URL, pool: DatabasePool, embedder: (any EmbeddingProvider)? = nil) {
        self.storeRoot = storeRoot
        self.pool = pool
        self.embedder = embedder
    }

    var wikiRoot: URL {
        storeRoot.appendingPathComponent("wiki", isDirectory: true)
    }

    var rawRoot: URL {
        storeRoot.appendingPathComponent("raw", isDirectory: true)
    }

    /// Ensures `wiki/` and `raw/` exist on disk. Safe to call repeatedly.
    func bootstrapDirectoriesIfNeeded() throws {
        let fm = FileManager.default
        for dir in [wikiRoot, rawRoot] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    func makeIndexer() -> Indexer {
        Indexer(wikiRoot: wikiRoot, pool: pool, embedder: embedder)
    }

    /// Full reindex plus regeneration of the derived `index.md` catalog.
    /// All production call sites go through this so the catalog can never
    /// drift from the SQLite index. The second reindex (only when the
    /// catalog bytes changed) is cheap — hash-diffing skips every other
    /// page — and converges: generation is deterministic and excludes the
    /// reserved pages, so a third pass would produce identical bytes.
    @discardableResult
    func reindexAll() async throws -> IndexReport {
        let report = try await makeIndexer().reindexAll()

        let entries: [IndexPageGenerator.Entry] = try await pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, title, summary FROM pages;")
                .map { .init(id: $0["id"], title: $0["title"], summary: $0["summary"]) }
        }
        let generated = IndexPageGenerator.generate(entries: entries)
        let indexURL = wikiRoot.appendingPathComponent("index.md")
        let onDisk = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? ""
        if generated != onDisk {
            try generated.write(to: indexURL, atomically: true, encoding: .utf8)
            _ = try await makeIndexer().reindexAll()
        }
        return report
    }

    /// Writes the default `wiki/AGENTS.md` conventions file — the schema
    /// layer of the LLM-wiki pattern — when none exists. Never overwrites:
    /// the file belongs to the user once created.
    func bootstrapSchemaFileIfNeeded() throws {
        let url = wikiRoot.appendingPathComponent("AGENTS.md")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try Self.defaultSchemaFile.write(to: url, atomically: true, encoding: .utf8)
    }

    static let defaultSchemaFile = """
    ---
    id: agents
    title: Conventions du wiki
    type: schema
    ---

    # Conventions du wiki

    Ce wiki est ta mémoire à long terme. Tu le maintiens toi-même en
    suivant ces règles. L'utilisateur peut les modifier — relis-les si
    besoin via `read_page("agents")`.

    ## Types de pages

    `type:` dans le frontmatter : `personne`, `concept`, `projet`,
    `note`, ou `resume-source` (synthèse d'une source de `raw/`).

    ## Règles

    - **Une page = un sujet.** Le titre est l'identité de la page.
    - **Jamais de doublon** : appelle `search_wiki` avant de créer une
      page ; si le sujet existe, mets à jour la page existante
      (`read_page` puis `write_wiki_page` avec le contenu complet fusionné).
    - **Relie** : chaque page créée ou modifiée doit contenir au moins un
      `[[lien]]` vers une autre page quand c'est pertinent.
    - **Cite tes sources** : liste les ids de `raw/` dans le frontmatter
      `sources: [id-1, id-2]`.
    - **Langue** : rédige en français.
    - **Fichiers réservés** : `index.md` (catalogue) et `log.md` (journal)
      sont générés par l'application — ne les modifie jamais.
    """
}
