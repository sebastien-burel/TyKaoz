---
title: TyKaoz
colorFrom: gray
colorTo: blue
sdk: static
pinned: false
---

<div align="center" style="background: linear-gradient(135deg, #2D3B52 0%, #4FB8C9 100%); color: #F7F5F0; padding: 36px 24px; border-radius: 16px;">
  <h1 style="margin: 0; font-size: 2.4em;">TyKaoz</h1>
  <p style="margin: 8px 0 0; font-size: 1.1em; opacity: 0.92;">
    Le chat IA local, privé, sur votre Mac.
  </p>
</div>

> **« Ty Kaoz »** — en breton, *ty* = la maison, *kaoz* = la causerie. Une maison
> pour discuter avec les IA, chez vous.

**TyKaoz** est une application macOS native (Apple Silicon) pour discuter avec
des modèles de langage — **locaux** comme distants. Pensée *privacy-first* : vos
conversations restent sur votre machine.

## Ce que c'est

- **Chat local et distant** — modèles MLX qui tournent sur votre Mac, ou
  fournisseurs distants (Ollama, OpenAI, Anthropic, Mistral, Google…).
- **Privé par défaut** — les conversations vivent sur disque, pas dans le cloud.
- **Natif Apple Silicon** — SwiftUI, streaming des tokens, pensé pour macOS.

## La suite (feuille de route)

Le chat n'est que la fondation. L'objectif : une couche **RAG / outils / agents**
par-dessus — notamment du **RAG local privé en français, avec sources**. On
construit proprement, on annonce quand c'est prêt, sans promesse en l'air.

## Ce dépôt d'organisation héberge

- [`models-manifest`](https://huggingface.co/TyKaoz/models-manifest) — le
  catalogue de modèles (`models.json`) que l'app lit au lancement.
- Des modèles **MLX quantifiés** prêts pour Apple Silicon (Gemma, BGE-M3,
  Mistral Small…), avec RAM mesurée en conditions réelles.

## L'app n'est pas encore disponible

TyKaoz est en développement. **Inscrivez-vous à la liste d'attente** pour être
prévenu·e dès l'ouverture :

### → [Rejoindre la liste d'attente](https://www.tykaoz.bzh)

---

<sub>Construit par <a href="https://www.haruni.net">Haruni</a> — Rennes, Bretagne.</sub>
