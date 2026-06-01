# PLAN_TYKAOZ.md

> Plan de développement — app macOS native de chat LLM, privacy-first.
> État au 2026-06-01 : phases 0-5 livrées (chat multi-provider, persistance,
> outils externes, plugins). Prochaine cible : Phase 6 — RAG documentaire.
> Ce plan avance **par paliers**. Chaque phase a des critères de succès
> vérifiables (cf. CLAUDE.md, guideline 4). On ne passe à la phase suivante
> qu'une fois les critères de la phase courante remplis.

---

## Cap stratégique (à garder en tête, pas à coder maintenant)

Le chat local seul n'est **pas un produit vendable** — c'est le terrain saturé
d'Ollama / LM Studio / Jan. La valeur de TyKaoz viendra de la couche
**RAG / outils / agents** par-dessus (hypothèse : RAG local privé en français
avec citation des sources, pour des pros qui ne peuvent pas envoyer leurs docs
dans le cloud).

**Conséquence sur ce plan :** les phases 1–4 construisent un socle de chat
*propre et extensible vers le RAG*. On ne cherche pas à le rendre vendable ;
on cherche à le rendre solide et à apprendre le terrain Swift + multi-backend.
La première milestone réellement testable commercialement est en Phase 6.

---

## Phase 0 — Cadrage & squelette projet — **livré**

**But :** un projet qui compile, vide, avec la structure modulaire en place.

- [x] Projet Xcode SwiftUI, app macOS, cible Apple Silicon.
- [x] Arborescence modulaire : `App/`, `UI/` (les 3 panneaux), `Core/`
      (logique métier testable), `Providers/` (backends LLM), `Persistence/`.
- [x] CLAUDE.md à la racine. Git initialisé, premier commit.
- [x] Cible de tests Swift Testing qui tourne (alignée Xcode 26).

**Critères de succès :**
- `xcodebuild` réussit ; l'app se lance sur une fenêtre vide.
- La suite de tests s'exécute (0 test, 0 échec).

---

## Phase 1 — Le shell UI (sans IA) — **livré**

**But :** la coquille à trois panneaux, branchée sur des données factices.

- [x] Layout 3 panneaux : réglages (serveur + modèle), sidebar conversations,
      panneau central de conversation.
- [x] Sidebar : liste de conversations *mockées*, sélection, nouvelle conv.
- [x] Panneau central : affichage de messages mockés (user / assistant),
      champ de saisie (pas encore connecté).
- [x] Tokens de marque appliqués (Ink/Slate/Tide, Fraunces/Inter Tight/Mono).

**Critères de succès :**
- On navigue entre 2-3 conversations mockées ; le panneau central reflète
  la sélection.
- Aucune logique réseau encore. UI seulement.

> Note modularité : à ce stade le modèle `Conversation`/`Message` est défini de
> façon neutre (pas de champ propre à Ollama). On reste minimal — pas de
> protocole provider tant qu'on n'a qu'un backend en vue (CLAUDE.md, archi).

---

## Phase 2 — Réglages & connexion Ollama distant — **livré**

**But :** configurer un serveur Ollama distant et lister ses modèles.

- [x] Écran réglages : URL du serveur Ollama (host:port), test de connexion.
- [x] Récupération de la liste des modèles disponibles (`/api/tags`).
- [x] Sélecteur de modèle alimenté par cette liste.
- [x] Persistance des réglages (URL, modèle choisi) sur disque.
- [x] Gestion d'erreur réseau réelle (serveur injoignable, timeout) —
      pas de gestion d'erreurs pour scénarios impossibles (CLAUDE.md §2).

**Critères de succès :**
- Saisir l'URL d'un Ollama distant joignable → la liste des modèles s'affiche.
- URL invalide → message d'erreur clair, pas de crash.
- Réglages persistés après redémarrage de l'app.

---

## Phase 3 — Chat réel avec streaming — **livré**

**But :** une vraie conversation, tokens en flux, contre Ollama.

- [x] Envoi d'un message → appel `/api/chat` d'Ollama en streaming.
- [x] Affichage incrémental des tokens (`AsyncStream`).
- [x] Historique de conversation envoyé en contexte à chaque tour.
- [x] Indicateur d'état (génération en cours, stop).
- [x] Le `OllamaProvider` est isolé dans `Providers/` derrière une frontière
      claire — **mais on n'écrit pas encore le protocole générique** (un seul
      backend ; on attend le 2e, cf. CLAUDE.md).

**Critères de succès :**
- Conversation multi-tours fonctionnelle, le modèle garde le contexte.
- Les tokens s'affichent au fil de l'eau, pas d'un bloc.
- Bouton stop interrompt la génération proprement.
- Tests unitaires sur le parsing des réponses streamées d'Ollama.

---

## Phase 4 — Persistance des conversations — **livré (sauf recherche)**

**But :** les conversations survivent au redémarrage.

- [x] Sauvegarde locale des conversations (JSON sur disque, choix fait en
      début de phase — SwiftData pas nécessaire à ce stade).
- [x] Chargement au lancement, mise à jour à chaque message.
- [x] Renommer / supprimer une conversation.
- [ ] Recherche plein-texte basique dans l'historique (était optionnel ;
      reporté tant qu'aucun usage réel ne l'a réclamé).

**Critères de succès :**
- Créer une conv, quitter, relancer → la conv et ses messages sont là.
- Supprimer une conv la retire du disque.
- Tests unitaires sur la couche de persistance (sérialisation aller-retour).

> **Fin du socle.** À ce stade TyKaoz est un client de chat Ollama propre,
> natif, modulaire. C'est le moment de décider de la suite sur du concret.

---

## Phase 5 — 2e backend : naissance de l'abstraction provider — **livré, au-delà**

**But :** ajouter un 2e backend, et **c'est seulement maintenant** qu'on conçoit
le protocole `LLMProvider` — avec 2 cas réels sous les yeux, pas 1.

- [x] 2e backend choisi : Mistral (cloud, SSE, OpenAI-compatible).
- [x] Protocole `LLMProvider` extrait à partir d'Ollama + Mistral.
- [x] `OllamaProvider` refactoré pour s'y conformer.
- [x] UI de sélection du provider dans les réglages (sidebar à N providers).

**Critères de succès :**
- On bascule de provider dans les réglages, le chat fonctionne avec les deux.
- Le protocole n'a pas de fuite spécifique à un provider (ex. pas de `pull`
  obligatoire imposé à Claude).
- Tests : un provider mocké implémente le protocole et passe les tests de chat.

**Au-delà du plan initial :** au lieu de s'arrêter à 2 providers, on en a
ajouté 7 supplémentaires un par un en validant que le protocole tient :
OpenAI, Anthropic, Google Gemini, DeepSeek, Apple Intelligence (Foundation
Models, on-device), Qwen Cloud (DashScope), z.ai (Zhipu GLM). Un
`OpenAICompatibleClient` partagé absorbe Mistral / OpenAI / DeepSeek /
Qwen / z.ai ; Anthropic, Google et Apple ont leur client dédié.

---

## Livré hors séquence — Outils externes (function calling)

Le plan initial plaçait les outils en *« Phases ultérieures »* après la RAG ;
en pratique ils ont été construits avant, parce qu'ils débloquent une boucle
agent-tools sur tous les providers et préparent le terrain RAG (un outil
`search_docs` se branchera de la même façon).

**Livré :**
- Boucle de tool calling multi-tours côté `ChatSession` (StreamEvent, max 10
  rounds, gestion d'erreurs comme `ToolResult` plutôt que throw).
- Émission + consommation des tool calls sur les 9 providers (chacun a son
  format : OpenAI-compatible `tool_calls`, Anthropic `content_block`,
  Google `functionDeclarations`, Ollama, Foundation Models natifs).
- 10 outils built-in : `current_datetime`, `current_location` (Core Location
  + reverse-geocoding), `fetch_url`, `web_search` (Brave), `list_directory`,
  `read_file`, `grep_files`, `save_memory`, `list_memories`, `read_memory`.
- *File spaces* autorisés (sandbox-friendly, bookmarks app-scope) bornant
  les outils fichiers.
- *Mémoire long terme* injectée comme system prompt à la demande.
- Système de **plugins HTTP** : drag-and-drop d'un manifeste JSON →
  outil exposé au modèle, secrets stockés dans le trousseau, templating
  d'URL/headers.
- UI : cartes d'appels d'outils repliables, étapes intermédiaires
  collapsées en fin de tour, toggles par outil dans les réglages,
  liste opt-in séparée pour Apple Intelligence (contexte 4k oblige).

**Reste à faire dans cette veine :** agents (boucles multi-étapes
autonomes), outils plus riches (édition de fichiers, exécution shell
encadrée, etc.) — non bloquants pour Phase 6.

---

## Phase 6 — RAG documentaire (première milestone vendable)

**But :** la vraie hypothèse produit. Glisser des documents, indexer en local,
répondre en citant les sources. C'est ici qu'on teste si quelqu'un paierait.

- [ ] Ingestion de documents (PDF/Markdown d'abord ; Word/Excel ensuite).
- [ ] Embeddings locaux (piste : bge-m3 via Ollama — déjà dans ton stack).
- [ ] Index vectoriel local + récupération.
- [ ] Réponses du chat enrichies par le contexte récupéré, **avec citation
      explicite des sources**.
- [ ] Soin particulier sur le français.

**Critères de succès (produit, pas seulement technique) :**
- Déposer 5-10 docs, poser une question → réponse correcte *avec sources*.
- **Test marché :** montrer ce MVP RAG à ~5 pros cibles (cabinets, indépendants
  manipulant des docs confidentiels) et observer s'ils dégainent la carte bleue.
  C'est ce signal — pas le code — qui valide ou invalide le cap stratégique.

---

## Phases ultérieures (esquisse, à re-cadrer le moment venu)

- **Agents** (boucles multi-étapes outillées, planification, retries).
- **Graph sur les conversations** (relations entre échanges/sujets,
  navigation par sujet plutôt que chronologique).
- **Recherche plein-texte** dans l'historique (reporté de la Phase 4).
- **iOS / iPadOS 26** : portage SwiftUI quand un besoin produit le justifie
  (cf. CLAUDE.md — code gardé portable mais targets non créés).
- **MLX local** : 11e backend possible, avec téléchargement des poids.
  Stresse l'abstraction provider différemment (pas de réseau, pas de `list_models`).
- **Packaging & distribution** : signature, notarisation, .dmg, compte
  développeur Apple, et seulement *si* le marché valide — RGPD/CNIL, CGU,
  modèle de prix. (Rappel : tout ce « reste » non-code est le vrai goulot pour
  un solo. Ne pas le sous-estimer.)

---

## Règles de conduite du plan

- On ne saute pas de phase. Critères de succès remplis = feu vert.
- À chaque début de phase : court plan d'attaque + critères de vérif (CLAUDE.md §4).
- Toute nouvelle dépendance externe se justifie explicitement.
- Le doute sur le « cœur produit » se tranche par le test marché en Phase 6,
  pas par plus de code en amont.
