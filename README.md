# TyKaoz

Application macOS native pour discuter avec des LLM locaux et distants.
Privacy-first, Apple Silicon.

Le nom vient du breton : *Ty* (la maison) + *Kaoz* (la causerie). Une maison
pour vos conversations avec les modèles. Construit par Haruni, à Rennes.

## Ce que c'est

Un client de chat natif (SwiftUI) qui parle à plusieurs backends LLM derrière
une interface à trois panneaux : réglages, liste des conversations, panneau de
discussion. Le streaming des tokens est traité de bout en bout.

Le chat local seul est un terrain saturé (Ollama, LM Studio, Jan) ; ce n'est
pas la finalité. La valeur visée de TyKaoz est la couche RAG / outils / agents
par-dessus — du RAG local privé en français avec citation des sources. Le chat
multi-provider est le socle, pas le produit fini.

## État

Socle livré (chat multi-provider, persistance, function calling, plugins).
La couche documentaire (wiki + embeddings locaux, RAG) est livrée côté code —
il reste à la confronter au marché. Le détail des paliers est dans
[`PLAN_TYKAOZ.md`](PLAN_TYKAOZ.md) et [`PLAN_TYKAOZ_WIKI.md`](PLAN_TYKAOZ_WIKI.md).

## Fonctionnalités

- **Chat en streaming** multi-tours, l'historique est renvoyé en contexte.
- **Providers de chat** (11) : Ollama (distant), Mistral, OpenAI, Anthropic,
  Google Gemini, DeepSeek, Qwen (DashScope), z.ai (GLM), un endpoint
  OpenAI-compatible générique, Apple Intelligence (Foundation Models,
  on-device) et MLX local (poids téléchargés). Un client OpenAI-compatible
  partagé sert les backends qui suivent ce format ; Anthropic, Google et Apple
  ont leur client dédié.
- **Vision & images** : entrée d'images (glisser-déposer, coller, joindre) vers
  les modèles VLM (MLX local et cloud) ; génération et édition d'images côté
  Gemini, OpenAI, Qwen, z.ai ; volet « Réflexion » repliable pour le raisonnement.
- **Génération d'images en local** via **ComfyUI** : provider texte→image branché
  sur un serveur ComfyUI ; chaque « modèle » est un workflow (JSON API) collé
  dans les réglages, avec paramètres et graine réglables.
- **Rendu des maths** : les notations LaTeX inline (`$…$`, `\(…\)`) sont
  converties en Unicode à l'affichage (le message stocké garde la source brute).
- **Persistance locale** des conversations (JSON sur disque, aucun cloud) :
  création, renommage, suppression, brouillons par conversation.
- **Outils (function calling)** sur tous les providers : `current_datetime`,
  `current_location`, `fetch_url`, `web_search` (Brave), `list_directory`,
  `read_file`, `grep_files`, mémoire long terme (`save`/`list`/`read_memory`),
  et les outils du wiki documentaire (`search_wiki`, `read_page`,
  `write_wiki_page`, `list_sources`, `read_source`).
- **Wiki / RAG on-device** : import de sources (PDF avec OCR, images OCR,
  markdown/texte, pages web) dans le wiki, distillation en pages markdown reliées
  par `[[wikilinks]]`, embeddings locaux (bge-m3 via MLX), récupération hybride
  vecteur/BM25/graphe avec citation des sources. Navigateur wiki (pages, graphe,
  audit/lint) et lecteur avec navigation par wikilinks. Export d'une conversation
  vers le wiki (« Wikifier »). Détail dans [`PLAN_TYKAOZ_WIKI.md`](PLAN_TYKAOZ_WIKI.md).
- **File spaces** : dossiers explicitement autorisés (bookmarks app-scope)
  qui bornent les outils fichiers, compatibles sandbox.
- **Plugins HTTP** : un manifeste JSON déposé dans l'app expose un outil au
  modèle. Templating d'URL/headers, secrets stockés dans le trousseau.
- **Clés API** stockées dans le trousseau macOS (`net.haruni.TyKaoz`).

## Prérequis

- macOS 26 (Tahoe) sur Apple Silicon.
- Xcode 26.
- Pour le chat local : un serveur Ollama joignable, ou des poids MLX
  téléchargés depuis l'app.
- Un checkout local du **Moddable SDK** (récent) pour la dépendance locale
  `../XSBridgeKit` : elle ne vendore pas les sources du moteur XS, elle les lie
  depuis `$MODDABLE` (voir l'étape de setup ci-dessous).

## Build

```sh
git clone git@github.com:sebastien-burel/TyKaoz.git
cd TyKaoz
```

Setup unique de la dépendance locale `../XSBridgeKit` (lie les sources XS depuis
ton checkout Moddable — sans ça, le moteur XS ne compile pas) :

```sh
export MODDABLE=/chemin/vers/moddable   # checkout Moddable récent
../XSBridgeKit/scripts/link-moddable.sh
```

Puis ouvrir et compiler :

```sh
open TyKaoz.xcodeproj
```

Compiler et lancer la cible **TyKaoz** dans Xcode, ou en ligne de commande :

```sh
xcodebuild build -project TyKaoz.xcodeproj -scheme TyKaoz -destination 'platform=macOS'
xcodebuild test  -project TyKaoz.xcodeproj -scheme TyKaoz -destination 'platform=macOS'
```

Les dépendances **distantes** sont gérées par Swift Package Manager et résolues
automatiquement à l'ouverture (GRDB, MLX Swift, swift-transformers, EventSource,
swift-markdown-ui, entre autres). Seule la dépendance locale `../XSBridgeKit`
demande l'étape `link-moddable.sh` ci-dessus.

## Architecture

- `App/` — point d'entrée, fenêtres, commandes.
- `UI/` — les trois panneaux (réglages, sidebar, chat) + wiki.
- `Core/` — logique métier testable (session de chat, conversations, réglages).
- `Providers/` — un backend LLM par dossier, derrière le protocole `LLMProvider`.
- `Persistence/` — stockage local des conversations, mémoires, wiki.
- `Tools/` — outils built-in, file spaces, plugins HTTP, outils wiki.

Principes : cœur agnostique du backend, abstraction introduite seulement quand
un 2e cas réel l'exige, persistance locale d'abord, streaming traité comme une
préoccupation de premier ordre. Détails dans [`CLAUDE.md`](CLAUDE.md).

## Tests

Logique non-UI couverte par Swift Testing (`TyKaozTests`). Les tests d'interface
(`TyKaozUITests`) sont en XCTest.

## Licence

Logiciel propriétaire. Copyright (c) 2026 Sébastien Burel (Haruni), tous
droits réservés. Voir [`LICENSE`](LICENSE).
