# PLAN_TYKAOZ_WIKI.md

LLM Wiki pour TyKaoz — concept Karpathy revisité avec finder RAG + vecteur + graphe, 100 % on-device, store SQLite/GRDB unique.

## Principe directeur

Le **markdown sur disque est canonique**. Le graphe et les vecteurs sont un **index dérivé, reconstructible à tout moment** depuis les `.md`. Règle non négociable :

> Le LLM n'écrit JAMAIS dans SQLite. Il ne lit que `raw/`, n'écrit que `wiki/*.md`. L'indexeur est une fonction pure `disque → SQLite`, à sens unique.

Conséquences : git-friendly, souverain, chiffrable SQLCipher, et un modèle qui ne peut pas corrompre l'index. On peut supprimer le `.sqlite` et le régénérer intégralement.

## Décisions verrouillées

- Source de vérité : markdown sur disque.
- Récupération + embeddings : 100 % on-device.
- Hôte : TyKaoz natif et autonome (IDE + agent + viewer), pas de dépendance Obsidian / Claude Code.
- Graphe : **wikilinks-only** au départ, schéma extensible vers relations typées.
- Store : **SQLite unique via GRDB** (pages + edges + chunks + vecteurs + FTS), pas de Kùzu/Cozo.
- Vecteurs : extension `sqlite-vec` chargée dans GRDB. Lexical : FTS5 (inclus).

## Arborescence sur disque

```
~/Library/Application Support/net.haruni.tykaoz/wiki-store/
├── raw/                      # sources brutes immuables (input du LLM)
│   └── <source-id>.{md,txt,pdf,...}
├── wiki/                     # pages markdown — CANONIQUE
│   ├── index.md
│   └── <slug>.md             # frontmatter + corps + [[wikilinks]]
└── index.sqlite              # DÉRIVÉ — régénérable, chiffré SQLCipher
```

Frontmatter de page (convention) :

```yaml
---
id: stable-slug-ou-uuid       # clé stable, ne change jamais
title: Titre lisible
type:                          # vide pour l'instant (réservé KG typé)
sources: [source-id-1, source-id-2]
created: 2026-06-01
updated: 2026-06-01
---
```

Lien interne : `[[Titre d'une autre page]]` ou `[[id|alias affiché]]`.

---

## Schéma GRDB

```sql
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

CREATE TABLE edges (
  src_page_id   TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
  dst_page_id   TEXT REFERENCES pages(id) ON DELETE CASCADE,   -- NULL = lien pendouillant
  dst_title_raw TEXT NOT NULL,
  rel_type      TEXT NOT NULL DEFAULT 'link',
  PRIMARY KEY (src_page_id, dst_title_raw, rel_type)
);
CREATE INDEX idx_edges_dst ON edges(dst_page_id);

CREATE TABLE chunks (
  id           INTEGER PRIMARY KEY,
  page_id      TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
  ordinal      INTEGER NOT NULL,
  heading_path TEXT,
  text         TEXT NOT NULL
);
CREATE INDEX idx_chunks_page ON chunks(page_id);

CREATE VIRTUAL TABLE vec_chunks USING vec0(
  chunk_id  INTEGER PRIMARY KEY,
  embedding FLOAT[768]
);
CREATE VIRTUAL TABLE fts_chunks USING fts5(text, content='chunks', content_rowid='id');

CREATE TABLE sources (
  id TEXT PRIMARY KEY, path TEXT NOT NULL, kind TEXT,
  hash TEXT NOT NULL, ingested_at DATETIME
);
CREATE TABLE page_sources (
  page_id   TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
  source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  PRIMARY KEY (page_id, source_id)
);
```

`chunks` est découplé de `vec_chunks` : changer de modèle d'embedding = reconstruire la seule table vectorielle, pas le reste.

---

## Phases d'implémentation

### Phase 0 — Socle GRDB + sqlite-vec

- [ ] Cible Swift, dépendances GRDB (+ SQLCipher).
- [ ] Bundler `sqlite-vec` (extension chargeable) ; charger via `Configuration.prepareDatabase`.
- [ ] Créer le schéma via migrations GRDB ; clé SQLCipher dans le Keychain.
- [ ] **Valider tôt** le chargement de l'extension en app macOS signée (entitlements). C'est le seul vrai piège d'intégration.

```swift
var config = Configuration()
config.prepareDatabase { db in
    try db.loadExtension(sqliteVecPath)   // path bundlé dans l'app
}
let dbQueue = try DatabaseQueue(path: storeURL.path, configuration: config)
```

Critère de sortie : un test insère un vecteur, fait un KNN, lit le résultat.

### Phase 1 — Indexeur (disque → SQLite)

- [ ] Parser frontmatter + corps markdown.
- [ ] Extraire les `[[wikilinks]]` → `edges` (résoudre `dst_title_raw` vers `dst_page_id` ; NULL si page absente).
- [ ] Chunking par headings (chunk = section, `heading_path` renseigné).
- [ ] Diff par `content_hash` : ne ré-embedde que les pages modifiées.
- [ ] Embedding local (voir Phase 5) → upsert `vec_chunks`, rebuild `fts_chunks`.
- [ ] Commande « rebuild full » : purge `index.sqlite`, ré-indexe tout `wiki/`.

### Phase 2 — File-watch incrémental

- [ ] `FSEvents` / `DispatchSource` sur `wiki/`.
- [ ] Debounce (le LLM peut écrire en rafale), puis ré-indexation des seuls fichiers touchés.
- [ ] Gestion suppression / renommage (cascade `ON DELETE`).

### Phase 3 — Finder hybride (le cœur)

Le gain sur le RAG plat vient de l'étape 2 : suivre les liens explicitement encodés par le wiki.

1. **Seeds** — embed la requête, KNN `vec_chunks` (k≈20) + BM25 `fts_chunks` (k≈20), fusion RRF → pages-graines.
2. **Expansion graphe** — CTE récursive bidirectionnelle, 1–2 sauts sur `edges`.
3. **Assemblage + rerank** — graines en plein texte, voisins en `summary` ; score = `sim_vectorielle + 1/(1+hops) + nb_connexions_graines + fraîcheur` ; MMR pour la diversité. **Pas de cross-encoder au départ.**

```sql
-- Expansion graphe (1-2 sauts)
WITH RECURSIVE reachable(page_id, depth) AS (
  SELECT :seedId, 0
  UNION
  SELECT CASE WHEN e.src_page_id = r.page_id THEN e.dst_page_id
              ELSE e.src_page_id END, r.depth + 1
  FROM edges e JOIN reachable r
    ON (e.src_page_id = r.page_id OR e.dst_page_id = r.page_id)
  WHERE r.depth < 2 AND e.dst_page_id IS NOT NULL
)
SELECT page_id, MIN(depth) AS hops FROM reachable
WHERE page_id IS NOT NULL GROUP BY page_id;
```

### Phase 4 — Boucle de tools (agent)

Outils exposés au LLM en function-calling natif. Lecture seule sauf `write_wiki_page`.

```swift
protocol WikiTools {
    // Lecture
    func searchWiki(query: String, k: Int) async throws -> [Retrieved]   // Phase 3
    func readPage(ref: PageRef) async throws -> Page                       // id ou titre
    func listSources() async throws -> [SourceMeta]
    func readSource(id: String) async throws -> String

    // Écriture — SEULE écriture autorisée, va sur disque, déclenche l'indexeur
    func writeWikiPage(path: String, content: String) async throws

    // Maintenance
    func lintWiki() async throws -> LintReport
}

struct Retrieved {
    let pageID: String
    let title: String
    let snippet: String
    let headingPath: String?     // pour citation précise
    let hops: Int                // distance graphe à la graine
    let score: Double
}
```

Boucle type : requête utilisateur → `searchWiki` → le LLM lit / raisonne → éventuellement `readSource` puis `writeWikiPage` pour créer/enrichir une page → l'indexeur reprend la main.

### Phase 5 — Embeddings on-device

- [ ] Choisir UN modèle et le figer (la dim verrouille `vec_chunks`).
  - MLX local sur Apple Silicon (zéro réseau) — privilégié.
  - ou Ollama : `nomic-embed-text` (768) / `mxbai-embed-large` (1024).
  - option : servir depuis le DGX Spark via SSH si on veut décharger le Mac.
- [ ] Normaliser (cosine), batcher l'embedding à l'ingestion.
- [ ] Changement de modèle = migration « rebuild vectoriel seul ».

### Phase 6 — `lint_wiki`

Moitié déterministe (SQL), moitié LLM :

- Orphelins : pages sans arête entrante (`pages` LEFT JOIN `edges` sur `dst_page_id`).
- Liens pendouillants : `edges.dst_page_id IS NULL`.
- Concepts manquants : `dst_title_raw` récurrents sans page correspondante → candidats à créer.
- (LLM) contradictions, obsolescence, doublons sémantiques.

### Phase 7 — Vue graphe native + lecteur

- [ ] Lecteur de page markdown (rendu + navigation par wikilinks).
- [ ] Vue graphe (force-directed) lue depuis `pages` / `edges`.
- [ ] Recherche interactive branchée sur le finder Phase 3.
- [ ] Panneau lint (Phase 6) avec actions « créer page manquante », « corriger lien ».

---

## Extension future (hors scope initial)

- **KG typé** : peupler `pages.type` et un vocabulaire fermé de `edges.rel_type` (ex. `precise`, `contredit`, `derive_de`) extrait par le LLM à l'ingestion. Le schéma le supporte déjà.
- **Reranker** : cross-encoder local seulement si la qualité plafonne.
- **Moteur graphe dédié** (Kùzu/Cozo) seulement si la traversée devient le goulot sur de très gros vaults.

## Risques / points de vigilance

- Chargement `sqlite-vec` en app signée → valider en Phase 0, pas plus tard.
- Cohérence dim embedding ↔ `vec_chunks` → un seul modèle, migration explicite sinon.
- Rafales d'écriture du LLM → debounce du file-watch.
- Résolution des wikilinks par titre fragile si les titres changent → préférer `[[id|alias]]` pour les liens critiques.
