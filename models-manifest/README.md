---
license: mit
tags:
  - tykaoz
  - mlx
  - apple-silicon
  - catalog
  - manifest
---

# TyKaoz — Manifeste de modèles

Ce dépôt héberge **`models.json`**, le catalogue de modèles locaux (MLX, Apple
Silicon) consommé par l'application macOS **TyKaoz**.

Éditer ce manifeste suffit à mettre à jour le sélecteur de modèles de tous les
clients **au lancement suivant** — sans release de l'app.

## Comment l'app le lit

TyKaoz récupère le fichier sur `main` :

```
https://huggingface.co/TyKaoz/models-manifest/resolve/main/models.json
```

Ordre de résolution côté client : **réseau > cache disque > fallback embarqué**.
Le catalogue vivant est lu sur `main` ; les poids de chaque modèle sont épinglés
par `revision` (quand le champ est renseigné) pour la reproductibilité.

## Schéma

Objet racine : `schema_version`, `updated_at`, `models[]`.

Champs communs d'un modèle :

| Champ | Type | Rôle |
|---|---|---|
| `id` | string | slug HuggingFace (ex. `mlx-community/bge-m3-mlx-4bit`) |
| `name` | string | nom affiché |
| `publisher` | string | éditeur d'origine |
| `description` | string | description courte (1 ligne) |
| `category` | enum | `embedding` \| `chat` |
| `runner` | enum | `mlx-embeddings` \| `mlx-lm` \| `mlx-vlm` |
| `quant` | string | quantification (`4-bit`, `8-bit`…) |
| `size_bytes` | int | taille approx. sur disque |
| `min_ram_gb` / `recommended_ram_gb` | int | RAM minimale / conseillée (dérivées du pic mesuré) |
| `measured_resident_gb` / `measured_peak_gb` | float | mémoire unifiée mesurée dans l'app (poids résidents / pic), optionnel |
| `recommended` | bool | mis en avant dans l'UI |
| `languages` | string[] | codes ISO |
| `revision` | string | SHA d'épinglage (optionnel) |

Spécifique **embedding** : `dimension`, `max_seq_len`.
Spécifique **chat** : `context_length`, `modalities`, `params_total`, `params_active`.

Les valeurs de RAM proviennent de `memory.txt` (pic mesuré par modèle, en
conditions réelles) : `min_ram_gb` = plus petite config Mac où le pic tient
(≤ 75 % de la RAM), `recommended_ram_gb` = config confortable (≤ 60 %).

Forward-compatibilité : un client plus ancien ignore proprement une `category`
ou un champ qu'il ne connaît pas (il ne plante pas).

<!-- MODELS:BEGIN -->

## Modèles du catalogue

_17 modèle(s). Section générée par `build_manifest.py` — ne pas éditer à la main._

| Modèle | `id` | Quant. | RAM min / conseillée | Mémoire (pic) | Taille |
|---|---|---|---|---|---|
| BGE-M3 (4-bit) | `TyKaoz/bge-m3-4bit` | 4-bit | — | — | 0.3 Go |
| BGE-M3 (6-bit) | `TyKaoz/bge-m3-6bit` | 6-bit | — | — | 0.5 Go |
| BGE-M3 (8-bit) | `TyKaoz/bge-m3-8bit` | 8-bit | — | — | 0.6 Go |
| Gemma 4 E2B Instruct (4-bit, VLM) | `TyKaoz/gemma-4-E2B-it-4bit` | 4-bit | 8 / 8 Go | 3,2 Gio | 3.6 Go |
| Gemma 4 E2B Instruct (6-bit, VLM) | `TyKaoz/gemma-4-E2B-it-6bit` | 6-bit | 8 / 8 Go | 3,9 Gio | 4.8 Go |
| Gemma 4 E2B Instruct (8-bit, VLM) | `TyKaoz/gemma-4-E2B-it-8bit` | 8-bit | 8 / 16 Go | 5,0 Gio | 5.9 Go |
| Gemma 4 E4B Instruct (4-bit, VLM) | `TyKaoz/gemma-4-E4B-it-4bit` | 4-bit | 8 / 8 Go | 4,3 Gio | 5.2 Go |
| Gemma 4 E4B Instruct (6-bit, VLM) | `TyKaoz/gemma-4-E4B-it-6bit` | 6-bit | 16 / 16 Go | 6,5 Gio | 7.1 Go |
| Gemma 4 E4B Instruct (8-bit, VLM) | `TyKaoz/gemma-4-E4B-it-8bit` | 8-bit | 16 / 16 Go | 7,8 Gio | 9.0 Go |
| Gemma 4 26B-A4B Instruct (4-bit, VLM) | `TyKaoz/gemma-4-26B-A4B-it-4bit` | 4-bit | 24 / 24 Go | 14,4 Gio | 15.4 Go |
| Gemma 4 26B-A4B Instruct (6-bit, VLM) | `TyKaoz/gemma-4-26B-A4B-it-6bit` | 6-bit | 32 / 48 Go | 20,2 Gio | 21.7 Go |
| Gemma 4 26B-A4B Instruct (8-bit, VLM) | `TyKaoz/gemma-4-26B-A4B-it-8bit` | 8-bit | 48 / 48 Go | 26,1 Gio | 28.0 Go |
| Mistral Small 3.2 24B Instruct (4-bit) | `TyKaoz/Mistral-Small-3.2-24B-Instruct-2506-4bit` | 4-bit | 24 / 24 Go | 12,8 Gio | 13.3 Go |
| Mistral Small 3.2 24B Instruct (6-bit) | `TyKaoz/Mistral-Small-3.2-24B-Instruct-2506-6bit` | 6-bit | 32 / 32 Go | 18,3 Gio | 19.2 Go |
| Mistral Small 3.2 24B Instruct (8-bit) | `TyKaoz/Mistral-Small-3.2-24B-Instruct-2506-8bit` | 8-bit | 32 / 48 Go | 23,8 Gio | 25.1 Go |
| LFM2.5 8B-A1B (4-bit) | `LiquidAI/LFM2.5-8B-A1B-MLX-4bit` | 4-bit | 8 / 8 Go | 4,5 Gio | 4.9 Go |
| LFM2.5 8B-A1B (8-bit) | `LiquidAI/LFM2.5-8B-A1B-MLX-8bit` | 8-bit | 16 / 16 Go | 8,8 Gio | 9.0 Go |

<!-- MODELS:END -->
