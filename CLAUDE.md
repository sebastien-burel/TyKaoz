# CLAUDE.md — TyKaoz

> Native macOS app for chatting with local & remote LLMs. Privacy-first, Apple Silicon.
> Built by Haruni (Rennes). This file guides Claude Code when working in this repo.

---

## Behavioral guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with the
project specifics below. **Tradeoff:** these bias toward caution over speed. For
trivial tasks, use judgment.

### 1. Think before coding
Don't assume. Don't hide confusion. Surface tradeoffs.
- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity first
Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility"/"configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.
- Test: "Would a senior engineer call this overcomplicated?" If yes, simplify.

### 3. Surgical changes
Touch only what you must. Clean up only your own mess.
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor what isn't broken. Match existing style.
- Notice unrelated dead code? Mention it — don't delete it.
- Remove imports/vars/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.
- Test: every changed line should trace to the request.

### 4. Goal-driven execution
Define success criteria. Loop until verified.
- "Add validation" → "Write tests for invalid inputs, then make them pass."
- "Fix the bug" → "Write a test that reproduces it, then make it pass."
- For multi-step tasks, state a brief plan with a verify step each.
- **When success criteria are well-defined (a test passes, output matches),
  loop autonomously without asking — reserve questions for genuine ambiguity in
  the goal itself.** (This project values uninterrupted loops on clear goals.)

Working if: fewer unnecessary diff lines, fewer rewrites for overcomplication,
clarifying questions come *before* implementation rather than after mistakes.

---

## What TyKaoz is

A native macOS chat client for LLMs. **The chat foundation is delivered:**
11 chat backends (Ollama, Mistral, OpenAI, Anthropic Claude, Google Gemini,
DeepSeek, Qwen, z.ai, a generic OpenAI-compatible endpoint, Apple Intelligence
on-device, and local MLX with model download), plus a local ComfyUI text→image
provider — each added *one at a time* behind a shared `LLMProvider` protocol.
The product focus is now the **RAG/wiki layer** over conversations (delivered in
code, cf. PLAN_TYKAOZ_WIKI.md); external tools and agents complete the roadmap.

**This is the strategic bet, stated honestly:** plain local chat is a crowded,
free space (Ollama, LM Studio, Jan). TyKaoz's differentiation is the
RAG/tools/agents layer on top — private local RAG in French with sources.
The chat milestone is the *foundation*, not the sellable product. Keep it clean
and extensible toward RAG, without over-engineering.

---

## Architecture principles

- **Backend-agnostic core.** The chat engine must not assume Ollama specifics.
  But — **don't abstract prematurely.** Keep the provider protocol *minimal*
  (only what Ollama needs) until the 2nd provider exists. Design the abstraction
  when adding provider #2, not before. Just don't make decisions now that would
  *exclude* Apple Intelligence (on-device, no "server"), Claude (SSE streaming,
  native tool use, no model `pull`), or MLX (local weights, download flow).
- **Three-pane UI shell:** settings (server + model choice), conversation
  sidebar, central chat panel. Keep these modular and independently testable.
- **Persistence is local-first.** Conversations live on disk; assume no cloud.
- **Streaming is a first-class concern**, not bolted on. Tokens arrive
  incrementally from the first backend onward.

---

## Stack & conventions

- **Language:** Swift, SwiftUI. Target **macOS 26** (Apple Silicon). iOS 26 /
  iPadOS 26 sont des cibles **planifiées plus tard** (multi-plateforme différé) —
  on garde le code SwiftUI portable mais on ne crée pas les targets iOS/iPadOS
  tant que le besoin produit ne l'exige pas. Apple Intelligence (Foundation
  Models framework) et MLX local sont désormais des providers intégrés
  (cf. PLAN_TYKAOZ.md).
- **Async:** Swift Concurrency (`async`/`await`, `AsyncStream` for tokens).
  No Combine unless there's a concrete reason.
- **No external dependencies** without explicit approval. Prefer the stdlib /
  system frameworks. Each added package must be justified.
- **XSBridgeKit (local SPM dependency `../XSBridgeKit`):** powers the JS agent
  runtime. It does **not** vendor the XS engine sources — they are symlinked from
  a local Moddable checkout. Before building/testing TyKaoz, run once (with a
  recent Moddable checkout):
  `export MODDABLE=/path/to/moddable && ../XSBridgeKit/scripts/link-moddable.sh`.
  Without it the XS engine won't compile. Consume only the Swift API
  (`XSEngine`, `HostBridge`, `HostResponder`) — never touch `xsSlot`/XS C macros.
- **State:** keep view models thin; business logic in plain testable types.
- **Tests:** Swift Testing (`import Testing`, `@Test`, `#expect`) — c'est
  ce que le template Xcode 26 ship et c'est ce qu'on utilise dans tout le
  projet. Les UI tests (`TyKaozUITests`) restent en XCTest, c'est ce que
  le template UI testing fournit. New backend logic and parsing get unit
  tests.

---

## Brand tokens (from the brand guidelines)

Apply these in UI work so it stays on-brand without re-explaining.

**Colors**
- Ink `#0E1420` — primary dark background
- Ink Soft `#1A1F2E` — cards, secondary surfaces
- Slate `#2D3B52` — "soul" color
- Tide `#4FB8C9` — AI accent, gradients
- Tide Bright `#6FD4E5` — indicators, cursor, links
- Foam `#B8E3E9` — halos, hover
- Paper `#F7F5F0` — text on dark / light background
- Ember `#E85D3A` — Haruni link, rare accent only

**Gradient (accent):** 135° Slate → Tide.

**Typography**
- Fraunces — display & titles (serif, editorial)
- Inter Tight — body & UI (≈90% of usage)
- JetBrains Mono — code, CLI, technical labels

**Voice:** short clear sentences, technically precise, honest about limits,
no marketing fluff ("révolutionnaire", "10x"), no decorative emoji, light Breton
touch (the name = "Ty" house + "Kaoz" chat/talk in Breton).

---

## Definition of done (chat milestone)

A change is done when:
1. It builds and runs on Apple Silicon.
2. New non-UI logic has unit tests that pass.
3. The diff is surgical (guideline 3).
4. No new dependency was added without approval.
5. Nothing was hardcoded to Ollama in a way that blocks future providers.
