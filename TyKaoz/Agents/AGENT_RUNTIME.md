# Runtime d'agents JavaScript — référence des appels JS↔Swift

> Doc interne développeur. Décrit le pont entre le code JavaScript d'un agent et
> l'hôte Swift : ce que le JS peut appeler (`host.*`), comment le natif charge et
> pilote un script, et le protocole bas niveau (`__nativeCall`). Cible :
> quelqu'un qui code la couche agent en Swift ou écrit/débogue des scripts.

TyKaoz exécute des agents écrits en JavaScript dans le moteur **XS** de Moddable,
enveloppé par le package SPM local `../XSBridgeKit`. On ne touche **jamais** aux
macros XS C (`xsSlot`, etc.) : on ne consomme que l'API Swift `XSEngine`,
`HostBridge`, `HostResponder`.

## Où vit le code

| Fichier | Rôle |
|---|---|
| `Agents/AgentRuntime.swift` | Exécute un agent standalone : un moteur par run, teardown à la fin. |
| `Agents/TyKaozHostBridge.swift` | Implémente `HostBridge` : le **prélude JS** (`host.*`) + le dispatch des appels natifs. |
| `Agents/AgentHostJSON.swift` | Helpers JSON purs (encode/décode aux frontières — que des strings JSON). |
| `Agents/JSToolBundle.swift` | Variante : un moteur long-lived qui expose des **outils** déclarés en JS. |
| `Agents/AgentRunner.swift` | Driver UI (`@MainActor @Observable`) : construit provider + `ToolRegistry`, appelle `AgentRuntime`. |
| `Persistence/AgentStore.swift` | Persiste les agents utilisateur (`agents.json`) + le template de démarrage. |
| `UI/Agents/AgentsView.swift` | Éditeur + console d'exécution. |

Le package XSBridgeKit est en dépendance SPM locale (`TyKaoz.xcodeproj`,
référence `../XSBridgeKit`) ; ses sources ne sont pas vendorées dans ce dépôt.

---

## 1. Contrat d'un agent

Un script d'agent **doit** définir `globalThis.run(input)`. Sa valeur de retour
est le résultat de l'agent (sérialisée en JSON). Il peut être `async`.

```js
globalThis.run = async function (input) {
  host.log("Entrée :", JSON.stringify(input));
  const reponse = await host.llm.chat(
    [{ role: "user", content: "Dis bonjour en breton." }],
    (delta) => { /* tokens au fil de l'eau */ }
  );
  return reponse;                 // → résultat de l'agent
};
```

Le template complet est dans `AgentStore.templateSource`
(`Persistence/AgentStore.swift:81`). Les agents sont **fournis par
l'utilisateur** (édités dans la fenêtre Agents), persistés dans
`Application Support/TyKaoz/agents.json`.

---

## 2. L'API `host.*` exposée au JS

C'est la surface ergonomique offerte aux scripts. Elle est **installée par le
prélude JS** de `TyKaozHostBridge.prelude` (`TyKaozHostBridge.swift:39`), pas par
le moteur : le moteur ne fournit que les primitives brutes (§4). Chaque méthode
async renvoie une `Promise` — donc `await` côté script.

| Appel JS | Clé native | Retour (résolu) | Erreur (rejet) |
|---|---|---|---|
| `host.llm.chat(messages, onToken?)` | `llm.chat` | texte complet concaténé (string) | pas de provider / erreur du provider |
| `host.tool.list()` | `tool.list` | `[{name, description, input_schema}]` | — |
| `host.tool.call(name, args?)` | `tool.call` | contenu du `ToolResult` (string) | `result.content` si l'outil échoue |
| `host.memory.save(title, content)` | `memory.save` | id (UUID string) | — |
| `host.memory.list()` | `memory.list` | `[{id, title}]` | — |
| `host.memory.read(id)` | `memory.read` | `{id, title, content}` ou `null` | id invalide |
| `host.log(...args)` | `log` | **synchrone**, `null` | — |

Détails :

- **`host.llm.chat(messages, onToken)`** — pilote le provider LLM *courant* de
  l'app (celui construit par `AgentRunner.buildTools` / `makeProvider`). `messages`
  est un tableau `{role, content}`. `onToken` est appelé pour chaque `textDelta`
  pendant le stream ; la promesse résout avec le texte complet. Les tool-calls du
  provider ne sont **pas** exposés ici (`tools: []`, `TyKaozHostBridge.swift:178`) —
  la boucle d'outils est pilotée par le JS via `host.tool.call`.
- **`host.tool.call(name, args)`** — exécute un outil du `ToolRegistry` (mêmes
  built-ins + plugins HTTP que le chat). `args` est un objet, encodé en JSON puis
  passé à l'outil. Si l'outil renvoie une erreur (`result.isError`), la promesse
  **rejette** avec le contenu (`TyKaozHostBridge.swift:208`).
- **`host.log(...)`** — seul appel **synchrone** (via `__nativeCallSync`). Écrit
  une ligne dans la console de la fenêtre Agents. Renvoie `null`.

> Il n'y a **pas** de `fetch`, `console.log`, ni `setTimeout` injectés. L'accès
> réseau passe uniquement par les outils du registry (`fetch_url`, `web_search`,
> plugins…). Pour ajouter une capacité, voir §7.

---

## 3. Cycle de vie d'un run (côté natif)

`AgentRuntime.run(script:input:timeout:)` (`AgentRuntime.swift:48`) :

1. Construit un `TyKaozHostBridge` (provider, `ToolRegistry`, `MemoryStore`, log).
2. Crée `XSEngine(host: bridge)` — l'init **évalue le prélude** (installe `host.*`).
3. `engine.eval(script)` — charge le script utilisateur.
4. `engine.eval("__runAgent(<inputJSON>)")` — appelle l'orchestrateur du prélude,
   qui invoque `globalThis.run(JSON.parse(inputJSON))`.
5. `run` termine → le prélude appelle la clé de contrôle `__finish` (résultat) ou
   `__fail` (erreur, avec `e.stack`).
6. `AgentSession` résout la `CheckedContinuation` correspondante.
7. **Teardown** : l'engine est relâché **hors du thread XS** (via
   `DispatchQueue.global().async` + `runUntilIdle`), car son `deinit` joint le
   thread XS et deadlockerait sinon (`AgentRuntime.swift:109`).

Un `DispatchWorkItem` arme le **timeout** (défaut 10 s dans `AgentRuntime`, 120 s
en prod via `AgentRunner.swift:51`) → `AgentError.timeout`.

**Il n'existe pas d'API « appeler une fonction JS par son nom ».** On appelle une
fonction en évaluant une source qui l'invoque (ex. `__runAgent(...)`,
`__callTool(...)`). Les arguments passent encodés en JSON dans la source.

---

## 4. Protocole d'appel bas niveau

Tout ce qui traverse la frontière est une **string UTF-8 contenant du JSON** (ou
un `uint32_t` d'id). Aucun slot XS ne remonte jusqu'à Swift. Doc de référence :
en-tête `AgentHostJSON.swift`.

Le moteur injecte **quatre globals** seulement (côté C, à la création de la
machine) :

| Global JS | Sens | Description |
|---|---|---|
| `__nativeCall(key, params, resolve, reject, onToken?)` | JS→Swift async | primitive asynchrone, style promesse |
| `__nativeCallSync(key, params)` | JS→Swift sync | primitive synchrone, renvoie la valeur inline |
| `host` | — | objet **vide** ; rempli par le prélude du consommateur |
| `print(x)` | JS→stdout | log + capturé dans `XSEngine.outputs` |

Le prélude enrobe chaque primitive dans une `Promise` (d'où `await host.*`) :

```js
host.tool.call = (name, args) =>
  new Promise((res, rej) => __nativeCall('tool.call', [name, args || {}], res, rej));
```

Côté Swift, `HostBridge` reçoit :

- `handle(key:paramsJSON:responder:)` — appel **async** ; on répond via le
  `HostResponder` : `.resolve(json)`, `.reject(json)`, `.emit(json)` (streaming).
- `handleSync(key:paramsJSON:) -> String` — appel **sync** ; on renvoie la string
  JSON directement.

`paramsJSON` est un **tableau positionnel** (`JSON.stringify` des params). Ex :
`tool.call` attend `[name, args]` ; `memory.save` attend `[title, content]`.
Décodage via `AgentJSON.params(...)` (`AgentHostJSON.swift`).

### Streaming (canal inverse)

Passer un 5e argument `onToken` à `__nativeCall`. Swift appelle
`responder.emit(json)` pour chaque token ; l'appel reste **ouvert** jusqu'à un
`resolve`/`reject` final. Utilisé par `host.llm.chat` (`TyKaozHostBridge.swift:181`).

### Clés de contrôle (`__`)

Les clés préfixées `__` ne sont pas des capacités : elles remontent à
`onControl` du runtime propriétaire (`TyKaozHostBridge.handle` `:129`).

| Clé | Émise par | Signification |
|---|---|---|
| `__finish` | prélude `__runAgent` | l'agent a terminé, params = `[résultatJSON]` |
| `__fail` | prélude `__runAgent` | l'agent a jeté, params = `[stack]` |
| `__toolResult` | prélude `__callTool` | résultat d'un outil JS, params = `[callId, resultJSON, error]` |

---

## 5. Bundles d'outils JS (`JSToolBundle`)

Alternative au run standalone : un moteur **long-lived** qui expose au reste de
l'app des outils *implémentés en JavaScript*. Le script doit définir :

```js
globalThis.tools = [
  { name, description, input_schema, run: async (args) => { /* ... */ } }
];
```

`JSToolBundle` lit `globalThis.tools` à l'init, puis invoque
`__callTool(name, argsJSON, callId)` (prélude `:99`) qui appelle `tool.run(args)`
et renvoie via la clé de contrôle `__toolResult`. Un `run` qui jette devient une
`ToolError`.

> État actuel : `JSToolBundle` n'est câblé que dans les tests — pas de
> consommateur en production. C'est le point d'accroche si on veut laisser
> l'utilisateur écrire des outils en JS (à la manière des plugins HTTP).

---

## 6. Threading & concurrence

XS est **mono-thread**. Chaque accès à la machine est marshallé sur un unique
thread dédié (`RunLoopThread`, `XSEngine.swift:19`). Conséquences :

- Les handlers de `HostBridge` tournent sur le **thread XS privé**, pas le main.
- Tout ce qui touche de l'état `@MainActor` (provider LLM, `ToolRegistry`,
  `MemoryStore`) hoppe via `Task { @MainActor in … }` puis répond avec le
  `HostResponder` (thread-safe depuis n'importe quelle queue).
- Les complétions async sont postées sur la run-loop du thread XS qui les applique
  (parse JSON → appelle le `resolve`/`reject` rooté, draine les microtasks).
- **Ne jamais** relâcher `XSEngine` sur le thread XS (deadlock au `deinit`) — cf.
  teardown §3.

Outils de diagnostic exposés par `XSEngine` : `pendingCount` (appels async en
vol), `rememberForgetCounts` (compta des roots GC, détection de fuite),
`runUntilIdle(timeout:)`, `runUntilIdleForcingGC(timeout:)`, `outputs`.

---

## 7. Ajouter une capacité `host.*` (guide)

Pour exposer une nouvelle fonction native au JS (ex. `host.wiki.search(q)`) :

1. **Prélude** — ajouter le wrapper JS dans `TyKaozHostBridge.prelude`, sur le
   modèle des existants (Promise autour de `__nativeCall('wiki.search', [q], …)`).
2. **Dispatch** — ajouter un `case "wiki.search":` dans `handle(...)` (async) ou
   `handleSync(...)` (sync).
3. **Handler** — décoder les params via `AgentJSON.params`, faire le travail (si
   état `@MainActor`, dans un `Task { @MainActor in }`), répondre avec
   `responder.resolve/reject(AgentJSON.string(...))`. Encoder **toujours** en JSON
   string via les helpers de `AgentHostJSON.swift`.
4. **Dépendance** — l'injecter dans l'init de `TyKaozHostBridge` (comme
   `tools`/`memory`) et la câbler depuis `AgentRunner.run(...)`.
5. **Test** — ajouter un cas dans `AgentRuntimeTests.swift` : un script `run`
   qui appelle `host.wiki.search` et vérifie le round-trip.

Règle : la frontière ne transporte que du JSON. Pas de type natif custom, pas de
slot XS.

---

## 8. Gestion des erreurs

- **JS → Swift** : un `throw` JS pendant `eval` est capturé (`xsTry`/`xsCatch`) et
  remonté en `XSError(message:)`, mappé en `AgentError.evaluation`. Une exception
  JS ne longjmp **jamais** dans Swift.
- **`run` qui jette / rejette** : capturé par le prélude → clé `__fail` →
  `AgentError.script(stack)`.
- **Swift → JS** : `responder.reject(json)` rejette la Promise côté JS (catchable
  dans le script). Reste dans le monde JS sauf si le script laisse remonter.
- `AgentError` (`AgentRuntime.swift:4`) : `.engineCreationFailed`, `.evaluation`,
  `.script`, `.timeout` (messages localisés FR).

---

## 9. Tests

- `TyKaozTests/AgentRuntimeTests.swift` — orchestrateur pilotant
  tool/LLM/memory + streaming, propagation d'erreur script, rejet d'outil
  inconnu catchable, équilibre des roots GC (zéro pending après appels
  concurrents).
- `TyKaozTests/JSToolBundleTests.swift` — outil JS exécuté via `ToolRegistry`,
  outil JS appelant le LLM, erreur JS → `ToolError`.

Ces tests sont la spec exécutable du protocole : les lire avant de modifier le
pont.
