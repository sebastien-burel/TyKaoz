#!/usr/bin/env python3
"""Construit le manifeste TyKaoz à partir de models.txt.

Pipeline :
  1. lit `models.txt` (un slug HuggingFace par ligne, `#` = commentaire) ;
  2. interroge l'API HuggingFace pour rafraîchir les champs techniques
     (revision, size_bytes, quant, runner, category, modalities) ;
  3. conserve les champs éditoriaux du `models.json` existant, indexés par
     `id` (name, description, publisher, RAM, recommended, languages,
     params_*, context_length, dimension, max_seq_len…) ;
  4. réécrit `models.json` (ordre = models.txt) ;
  5. réécrit la table des modèles dans `README.md` (entre marqueurs) ;
  6. pousse `models.json` et `README.md` sur le dépôt HuggingFace via `hf`.

Stdlib uniquement ; l'upload réutilise la session `hf auth` existante.

Usage :
  python3 build_manifest.py              # génère + upload
  python3 build_manifest.py --no-upload  # génère seulement (ou --dry-run)
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from collections import OrderedDict
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS_TXT = HERE / "models.txt"
MODELS_JSON = HERE / "models.json"
README_MD = HERE / "README.md"
MEMORY_TXT = HERE / "memory.txt"

# Real Mac configs used to size the RAM floor/recommendation (Go).
RAM_TIERS = [8, 16, 24, 32, 48, 64, 96, 128]

HF_REPO = "TyKaoz/models-manifest"
SCHEMA_VERSION = 2

MODELS_BEGIN = "<!-- MODELS:BEGIN -->"
MODELS_END = "<!-- MODELS:END -->"

# Champs recalculés depuis HuggingFace à chaque build (écrasent l'existant).
TECHNICAL_FIELDS = {"revision", "size_bytes", "quant", "runner", "category", "modalities"}

# Champs éditoriaux attendus pour un modèle de chat (sert au diagnostic).
EDITORIAL_REQUIRED = ["name", "description", "publisher", "min_ram_gb",
                      "recommended_ram_gb", "recommended", "languages"]

# Ordre d'écriture des clés dans le JSON (les clés inconnues suivent).
KEY_ORDER = [
    "id", "name", "publisher", "description", "category", "runner", "quant",
    "min_ram_gb", "recommended_ram_gb", "measured_resident_gb", "measured_peak_gb",
    "recommended", "languages",
    "params_total", "params_active", "context_length", "modalities",
    "dimension", "max_seq_len", "revision", "size_bytes",
]


# --------------------------------------------------------------------------
# Mémoire mesurée (memory.txt)
# --------------------------------------------------------------------------

def load_memory() -> dict:
    """Parse `memory.txt` lines like:
        <id> : Mémoire mesurée — résident 3,2 GB · pic 3,25 GB
    into {id: {"resident": 3.2, "peak": 3.25}} (Gio, mesuré dans l'app).
    """
    mem: dict = {}
    if not MEMORY_TXT.exists():
        return mem
    for raw in MEMORY_TXT.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        model_id, rest = line.split(":", 1)
        res = re.search(r"résident\s*([\d.,]+)", rest)
        peak = re.search(r"pic\s*([\d.,]+)", rest)
        num = lambda m: float(m.group(1).replace(",", ".")) if m else None
        mem[model_id.strip()] = {"resident": num(res), "peak": num(peak)}
    return mem


def derive_ram(peak_gb: float) -> tuple[int, int]:
    """From the measured peak, the smallest Mac config that runs it
    (≤75 % of RAM, leaving room for the OS + a VLM image) and a
    comfortable recommendation (≤60 %)."""
    min_ram = next((t for t in RAM_TIERS if peak_gb <= 0.75 * t), RAM_TIERS[-1])
    rec_ram = next((t for t in RAM_TIERS if peak_gb <= 0.60 * t), RAM_TIERS[-1])
    return min_ram, max(rec_ram, min_ram)


# --------------------------------------------------------------------------
# HuggingFace
# --------------------------------------------------------------------------

def _hf_token() -> str | None:
    tok = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    if tok:
        return tok.strip()
    token_file = Path.home() / ".cache" / "huggingface" / "token"
    if token_file.exists():
        return token_file.read_text(encoding="utf-8").strip() or None
    return None


def fetch_model_info(model_id: str, token: str | None) -> dict:
    url = f"https://huggingface.co/api/models/{model_id}?blobs=true"
    req = urllib.request.Request(url, headers={"User-Agent": "tykaoz-manifest-builder"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        raise SystemExit(f"✗ {model_id}: HTTP {exc.code} ({exc.reason}). "
                         f"Modèle privé/inexistant ou token manquant ?") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"✗ {model_id}: réseau indisponible ({exc.reason}).") from exc


def derive_runner(info: dict) -> str:
    tags = set(info.get("tags", []))
    for runner in ("mlx-vlm", "mlx-embeddings", "mlx-lm"):
        if runner in tags:
            return runner
    pipeline = info.get("pipeline_tag", "")
    if pipeline in ("feature-extraction", "sentence-similarity"):
        return "mlx-embeddings"
    if pipeline == "image-text-to-text":
        return "mlx-vlm"
    return "mlx-lm"


def derive_quant(info: dict, model_id: str) -> str | None:
    bits = (info.get("config") or {}).get("quantization_config", {}).get("bits")
    if isinstance(bits, int):
        return f"{bits}-bit"
    # repli : déduit du slug (…-4bit, …-8bit)
    for token in model_id.lower().replace("_", "-").split("-"):
        if token.endswith("bit") and token[:-3].isdigit():
            return f"{token[:-3]}-bit"
    return None


def derive_modalities(info: dict) -> list[str]:
    pipeline = info.get("pipeline_tag", "")
    if pipeline == "image-text-to-text":
        return ["text", "image"]
    return ["text"]


def derive_publisher(info: dict) -> str | None:
    base = (info.get("cardData") or {}).get("base_model")
    if isinstance(base, list):
        base = base[0] if base else None
    if isinstance(base, str) and "/" in base:
        org = base.split("/", 1)[0]
        return {"google": "Google", "meta-llama": "Meta", "mistralai": "Mistral AI",
                "qwen": "Qwen", "deepseek-ai": "DeepSeek"}.get(org.lower(), org.capitalize())
    return None


# --------------------------------------------------------------------------
# Build d'un modèle (fusion technique + éditorial)
# --------------------------------------------------------------------------

def build_model(model_id: str, info: dict, existing: dict, memory: dict,
                warnings: list[str]) -> OrderedDict:
    # On repart de l'éditorial existant pour conserver tout champ inconnu.
    merged: dict = dict(existing.get(model_id, {}))
    is_new = model_id not in existing

    runner = derive_runner(info)
    category = "embedding" if runner == "mlx-embeddings" else "chat"
    size_bytes = sum(s.get("size", 0) or 0 for s in info.get("siblings", []))

    merged["id"] = model_id
    merged["category"] = category
    merged["runner"] = runner
    merged["revision"] = info.get("sha")
    merged["size_bytes"] = size_bytes
    quant = derive_quant(info, model_id)
    if quant:
        merged["quant"] = quant
    if category == "chat":
        merged["modalities"] = derive_modalities(info)

    # Valeurs par défaut pour un nouveau modèle (à compléter ensuite).
    if is_new:
        merged.setdefault("name", model_id.split("/")[-1])
        merged.setdefault("publisher", derive_publisher(info) or "")
        merged.setdefault("description", "")
        merged.setdefault("recommended", False)
        card_langs = (info.get("cardData") or {}).get("language") or []
        merged.setdefault("languages", card_langs)

    # Normalise : le model card HF peut renvoyer `language` en chaîne unique
    # ("en") au lieu d'un tableau, ce que l'app refuse de décoder (champ
    # écarté en silence). On garantit une liste de chaînes.
    langs = merged.get("languages")
    if isinstance(langs, str):
        merged["languages"] = [langs]

    # Mémoire mesurée (memory.txt) = source de vérité RAM quand dispo :
    # on stocke le pic/résident et on en dérive min/recommended_ram_gb.
    mem = memory.get(model_id)
    if mem and mem.get("peak"):
        merged["measured_peak_gb"] = round(mem["peak"], 2)
        if mem.get("resident"):
            merged["measured_resident_gb"] = round(mem["resident"], 2)
        min_ram, rec_ram = derive_ram(mem["peak"])
        merged["min_ram_gb"] = min_ram
        merged["recommended_ram_gb"] = rec_ram

    if is_new:
        missing = [f for f in EDITORIAL_REQUIRED if not merged.get(f) and merged.get(f) != 0]
        if missing:
            warnings.append(f"  • {model_id} (nouveau) — à compléter : {', '.join(missing)}")

    # Réordonne les clés.
    ordered = OrderedDict()
    for key in KEY_ORDER:
        if key in merged:
            ordered[key] = merged[key]
    for key, value in merged.items():
        if key not in ordered:
            ordered[key] = value
    return ordered


# --------------------------------------------------------------------------
# README
# --------------------------------------------------------------------------

def human_size(n: int) -> str:
    gb = n / 1_000_000_000
    return f"{gb:.1f} Go"


def render_models_section(models: list[dict]) -> str:
    lines = [
        MODELS_BEGIN,
        "",
        "## Modèles du catalogue",
        "",
        f"_{len(models)} modèle(s). Section générée par `build_manifest.py` —"
        " ne pas éditer à la main._",
        "",
        "| Modèle | `id` | Quant. | RAM min / conseillée | Mémoire (pic) | Taille |",
        "|---|---|---|---|---|---|",
    ]
    for m in models:
        mn, rec = m.get("min_ram_gb"), m.get("recommended_ram_gb")
        ram_str = f"{mn} / {rec} Go" if mn and rec else "—"
        peak = m.get("measured_peak_gb")
        peak_str = f"{peak:.1f} Gio".replace(".", ",") if peak else "—"
        lines.append(
            f"| {m.get('name', '')} | `{m['id']}` | {m.get('quant', '—')} | "
            f"{ram_str} | {peak_str} | {human_size(m.get('size_bytes', 0))} |"
        )
    lines += ["", MODELS_END]
    return "\n".join(lines)


def update_readme(models: list[dict]) -> None:
    section = render_models_section(models)
    text = README_MD.read_text(encoding="utf-8") if README_MD.exists() else ""
    if MODELS_BEGIN in text and MODELS_END in text:
        head, rest = text.split(MODELS_BEGIN, 1)
        _, tail = rest.split(MODELS_END, 1)
        text = head + section + tail
    else:
        text = text.rstrip() + "\n\n" + section + "\n"
    README_MD.write_text(text, encoding="utf-8")


# --------------------------------------------------------------------------
# Upload
# --------------------------------------------------------------------------

def upload(today: str) -> None:
    for path in (MODELS_JSON, README_MD):
        print(f"↑ upload {path.name} → {HF_REPO}")
        subprocess.run(
            ["hf", "upload", HF_REPO, str(path), path.name,
             "--commit-message", f"chore: update manifest ({today})"],
            check=True,
        )


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def read_ids() -> list[str]:
    if not MODELS_TXT.exists():
        raise SystemExit(f"✗ introuvable : {MODELS_TXT}")
    ids = []
    for raw in MODELS_TXT.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            ids.append(line)
    if not ids:
        raise SystemExit("✗ models.txt est vide.")
    return ids


def load_existing() -> dict:
    if not MODELS_JSON.exists():
        return {}
    data = json.loads(MODELS_JSON.read_text(encoding="utf-8"))
    return {m["id"]: m for m in data.get("models", []) if "id" in m}


def main() -> int:
    parser = argparse.ArgumentParser(description="Construit et publie le manifeste TyKaoz.")
    parser.add_argument("--no-upload", "--dry-run", dest="no_upload", action="store_true",
                        help="génère les fichiers sans pousser sur HuggingFace")
    args = parser.parse_args()

    ids = read_ids()
    existing = load_existing()
    memory = load_memory()
    token = _hf_token()
    warnings: list[str] = []

    print(f"→ {len(ids)} modèle(s) depuis models.txt · {len(memory)} mesure(s) mémoire")
    models = []
    for model_id in ids:
        print(f"  · {model_id}")
        info = fetch_model_info(model_id, token)
        models.append(build_model(model_id, info, existing, memory, warnings))

    today = datetime.date.today().isoformat()
    manifest = OrderedDict([
        ("schema_version", SCHEMA_VERSION),
        ("updated_at", today),
        ("models", models),
    ])
    MODELS_JSON.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8")
    print(f"✓ {MODELS_JSON.name} écrit ({len(models)} modèles, updated_at={today})")

    update_readme(models)
    print(f"✓ {README_MD.name} mis à jour")

    if warnings:
        print("\n⚠ champs éditoriaux à compléter manuellement :")
        print("\n".join(warnings))

    if args.no_upload:
        print("\n(--no-upload) génération seule, pas d'upload.")
        return 0

    print()
    upload(today)
    print("✓ publié sur HuggingFace.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
