# Agent Runtime

TyKaoz runs JavaScript agents inside the **XS (Moddable)** engine, embedded via
**XSBridgeKit**. An agent is JS that drives the LLM, tools and memory through a
`host.*` surface. Everything crossing the JS↔Swift boundary is a **UTF-8 JSON
string** (or an opaque `uint32_t` call id) — never an `xsSlot`.

## Architecture (XSBridgeKit `simplify`)

XSBridgeKit no longer offers a Swift `HostBridge` protocol or a JS prelude. Host
capabilities are now installed as **C host functions** (against `xs.h`) that
call **Swift `@_cdecl`** counterparts. TyKaoz supplies these in three layers:

- **`TyKaozHostC`** (local SwiftPM package, `../TyKaozHostC`) — the C host
  functions. Each marshals its JS arguments to plain C and, for async calls,
  creates its Promise via `xsBridgePromise`, then hands `(bridge, id, json)` to
  a Swift `@_cdecl` function. Installed by `xsBridgeTyKaozInstall(machine)`.
- **`TyKaozHost.swift`** — the `@_cdecl` entry points and the business logic
  (`TyKaozHost`: provider, tools, memory, log). Each entry point recovers the
  `TyKaozHost` from the bridge context (`xsBridgeGetContext`) and settles the
  call via `HostReply` (`xsBridgeComplete` / `xsBridgeEmitToken`). Also holds
  `XSEngine.tyKaoz(host:)`, which creates an engine, installs the host, points
  the bridge context at the host, and evals the JS orchestrator.
- **`AgentModuleStaging.swift`** — module staging + the JS orchestrator string.

The XSBridgeKit product `XSBridge` (exposed for this) provides the flat settle
functions; `XSBridgeKit` provides `XSEngine`.

## `host.*` surface (unchanged for agent authors)

Built as C primitives plus a small JS shim (`AgentOrchestrator.js`, eval'd once):

| JS call | Kind | Resolves with | Rejects on |
|---|---|---|---|
| `host.llm.chat(messages, opts?, onToken?)` | async + stream | final answer text | no provider / provider error / unknown tool |
| `host.tool.list()` | async | `[{name, description, input_schema}]` | — |
| `host.tool.call(name, args?)` | async | the tool's result content | tool error |
| `host.memory.save(title, content)` | async | new memory id | — |
| `host.memory.list()` | async | `[{id, title}]` | — |
| `host.memory.read(id)` | async | `{id, title, content}` or `null` | invalid id |
| `host.log(...args)` | sync | — | — |

`host.llm.chat`: `opts.tools` is an array of tool **names** (a subset of the
registry); the host resolves them to `ToolSpec`s (unknown name → reject
`unknown tool: <name>`) and runs the **native tool loop** (up to
`maxToolRounds = 20`), executing each `.toolCall`, feeding the `.toolResult`
back, re-prompting, and resolving with the final text. Back-compat:
`chat(messages, onToken)` (a function 2nd arg) still streams. `onToken` receives
each text delta. Under the hood the shim calls the C primitive `host.__chat`.

## Running an agent

`AgentRuntime.run(script:input:timeout:libraryRoot:)`:

1. **Stage** the run (`AgentModuleStaging`): a per-run temp dir where the script
   is written as `agent.js` and the `libraryRoot` folder is copied next to it,
   so the agent can `import { x } from "./x.js"` (explicit relative + extension —
   XSBridgeKit's loader does not guess bare/extensionless specifiers).
2. Build a `TyKaozHost`, create the engine (`XSEngine.tyKaoz(host:)`).
3. `eval("__runAgent(<agentPath>, <inputJSON>)")` — the orchestrator dynamic-
   `import()`s the staged agent (module goal, so static `import ... from` works),
   calls its `run(input)` (a named `export run`, `export default`, or
   `globalThis.run`), then reports the result via
   `host.__report(JSON.stringify(r))` or `host.__fail(stack)` on throw/rejection.
4. `host.__report`/`__fail` are C host functions → `@_cdecl` → resolve the
   `AgentSession` continuation. The engine is released **off** the XS thread (its
   deinit joins that thread) and the staging dir is cleaned up.

`run` returns the result as a JSON string (a string result comes back
JSON-quoted). Errors: `AgentError = .engineCreationFailed | .evaluation |
.script | .timeout`.

## JS tools (`JSToolBundle`)

A persistent engine exposing JS-declared tools (`globalThis.tools = [{name,
description, input_schema, run}]`) as native `Tool`s. `call(name, args)` evals
`__callTool(name, argsJSON, callId)`; the orchestrator runs the JS tool and
reports via `host.__toolResult(callId, resultJSON, error)` — a C host function →
`@_cdecl xsbTyToolResult` → the bundle's `waiters`.

## Control channel (host functions, not a prelude)

`host.__report` (agent result), `host.__fail` (agent error), `host.__toolResult`
(JS-tool result) are ordinary C host functions installed alongside the rest.

## Threading

XS is single-threaded; `@_cdecl` entry points run on the engine's private XS
thread. Work touching `@MainActor` state (provider, `ToolRegistry`,
`MemoryStore`) hops via `Task { @MainActor in … }` and settles through the
thread-safe `HostReply`, which wakes the engine's run loop. Never release
`XSEngine` on the XS thread.

## Notes

- **Module confinement**: staging copies only `libraryRoot`, so relative imports
  can't escape it; absolute-path imports (`import "/…"`) are **not** blocked by
  the engine's filesystem loader (accepted tradeoff).
- **`ModuleResolver.swift`** is no longer used by the runtime (staging replaced
  the Swift-driven resolver). It and its tests remain as a pure, tested utility;
  remove if you're sure nothing else will want it.
