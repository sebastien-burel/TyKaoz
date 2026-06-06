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
La couche documentaire (wiki + embeddings locaux, RAG) est en cours.
Le détail des paliers est dans [`PLAN_TYKAOZ.md`](PLAN_TYKAOZ.md) et
[`PLAN_TYKAOZ_WIKI.md`](PLAN_TYKAOZ_WIKI.md).

## Fonctionnalités

- **Chat en streaming** multi-tours, l'historique est renvoyé en contexte.
- **Providers** : Ollama (distant), Mistral, OpenAI, Anthropic, Google Gemini,
  DeepSeek, Qwen (DashScope), z.ai (GLM), un endpoint OpenAI-compatible
  générique, Apple Intelligence (Foundation Models, on-device) et MLX local
  (poids téléchargés). Un client OpenAI-compatible partagé sert les backends
  qui suivent ce format ; Anthropic, Google et Apple ont leur client dédié.
- **Persistance locale** des conversations (JSON sur disque, aucun cloud) :
  création, renommage, suppression.
- **Outils (function calling)** sur tous les providers : `current_datetime`,
  `current_location`, `fetch_url`, `web_search` (Brave), `list_directory`,
  `read_file`, `grep_files`, mémoire long terme (`save`/`list`/`read_memory`),
  et les outils du wiki documentaire.
- **File spaces** : dossiers explicitement autorisés (bookmarks app-scope)
  qui bornent les outils fichiers, compatibles sandbox.
- **Plugins HTTP** : un manifeste JSON déposé dans l'app expose un outil au
  modèle. Templating d'URL/headers, secrets stockés dans le trousseau.
  Exemples fournis dans [`plugins/`](plugins/).
- **Clés API** stockées dans le trousseau macOS (`net.haruni.TyKaoz`).

## Prérequis

- macOS 26 (Tahoe) sur Apple Silicon.
- Xcode 26.
- Pour le chat local : un serveur Ollama joignable, ou des poids MLX
  téléchargés depuis l'app.

## Build

```sh
git clone git@github.com:sebastien-burel/TyKaoz.git
cd TyKaoz
open TyKaoz.xcodeproj
```

Compiler et lancer la cible **TyKaoz** dans Xcode, ou en ligne de commande :

```sh
xcodebuild build -project TyKaoz.xcodeproj -scheme TyKaoz -destination 'platform=macOS'
xcodebuild test  -project TyKaoz.xcodeproj -scheme TyKaoz -destination 'platform=macOS'
```

Les dépendances sont gérées par Swift Package Manager et résolues
automatiquement à l'ouverture (GRDB, MLX Swift, swift-transformers, EventSource,
swift-markdown-ui, entre autres). Aucune installation manuelle.

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
