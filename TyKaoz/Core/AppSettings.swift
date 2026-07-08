import Foundation
import Observation

@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var selectedProviderID: String {
        didSet { defaults.set(selectedProviderID, forKey: Keys.selectedProvider) }
    }

    // MARK: - Anthropic

    var anthropicAPIKey: String {
        didSet { KeychainStore.set(anthropicAPIKey, account: KeychainAccounts.anthropicAPIKey) }
    }

    var anthropicModel: String? {
        didSet { defaults.set(anthropicModel, forKey: Keys.anthropicModel) }
    }

    // MARK: - DeepSeek

    var deepseekAPIKey: String {
        didSet { KeychainStore.set(deepseekAPIKey, account: KeychainAccounts.deepseekAPIKey) }
    }

    var deepseekModel: String? {
        didSet { defaults.set(deepseekModel, forKey: Keys.deepseekModel) }
    }

    // MARK: - Google

    var googleAPIKey: String {
        didSet { KeychainStore.set(googleAPIKey, account: KeychainAccounts.googleAPIKey) }
    }

    var googleModel: String? {
        didSet { defaults.set(googleModel, forKey: Keys.googleModel) }
    }

    // MARK: - Local OpenAI-compatible (vLLM / LM Studio / llama.cpp)

    /// Raw URL string the user types in the settings panel. Validated
    /// at use site through `localOpenAIBaseURL`. Empty when no local
    /// server is configured.
    var localOpenAIBaseURLString: String {
        didSet { defaults.set(localOpenAIBaseURLString, forKey: Keys.localOpenAIBaseURL) }
    }

    /// Optional bearer token. Most self-hosted servers don't require
    /// one; cloud-like deployments behind a gateway might.
    var localOpenAIAPIKey: String {
        didSet { KeychainStore.set(localOpenAIAPIKey, account: KeychainAccounts.localOpenAIAPIKey) }
    }

    var localOpenAIModel: String? {
        didSet { defaults.set(localOpenAIModel, forKey: Keys.localOpenAIModel) }
    }

    /// Parsed, validated base URL. `nil` when the string is empty or
    /// malformed — providers/UI use this to know if the slot is
    /// configured.
    var localOpenAIBaseURL: URL? {
        let trimmed = localOpenAIBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }

    // MARK: - Mistral

    var mistralAPIKey: String {
        didSet { KeychainStore.set(mistralAPIKey, account: KeychainAccounts.mistralAPIKey) }
    }

    var mistralModel: String? {
        didSet { defaults.set(mistralModel, forKey: Keys.mistralModel) }
    }

    // MARK: - Ollama

    var serverURLString: String {
        didSet { defaults.set(serverURLString, forKey: Keys.serverURL) }
    }

    var selectedModel: String? {
        didSet { defaults.set(selectedModel, forKey: Keys.selectedModel) }
    }

    var serverURL: URL? {
        let trimmed = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return nil
        }
        return url
    }

    // MARK: - OpenAI

    var openaiAPIKey: String {
        didSet { KeychainStore.set(openaiAPIKey, account: KeychainAccounts.openaiAPIKey) }
    }

    var openaiModel: String? {
        didSet { defaults.set(openaiModel, forKey: Keys.openaiModel) }
    }

    // MARK: - Qwen Cloud

    var qwenAPIKey: String {
        didSet { KeychainStore.set(qwenAPIKey, account: KeychainAccounts.qwenAPIKey) }
    }

    var qwenModel: String? {
        didSet { defaults.set(qwenModel, forKey: Keys.qwenModel) }
    }

    // MARK: - z.ai (Zhipu GLM)

    var zaiAPIKey: String {
        didSet { KeychainStore.set(zaiAPIKey, account: KeychainAccounts.zaiAPIKey) }
    }

    var zaiModel: String? {
        didSet { defaults.set(zaiModel, forKey: Keys.zaiModel) }
    }

    // MARK: - ComfyUI (image generation)

    var comfyuiBaseURLString: String {
        didSet { defaults.set(comfyuiBaseURLString, forKey: Keys.comfyuiBaseURL) }
    }

    /// Optional bearer token. ComfyUI core has no auth; a deployment behind
    /// a gateway might.
    var comfyuiAPIKey: String {
        didSet { KeychainStore.set(comfyuiAPIKey, account: KeychainAccounts.comfyuiAPIKey) }
    }

    /// Active workflow name (the "model").
    var comfyuiModel: String? {
        didSet { defaults.set(comfyuiModel, forKey: Keys.comfyuiModel) }
    }

    /// Named ComfyUI workflows (API-format JSON). Each name is a selectable
    /// "model" in the picker; the JSON is the graph carrying a `%prompt%`
    /// marker. Stored as a `[String: String]` dictionary in UserDefaults.
    var comfyuiWorkflows: [String: String] {
        didSet { defaults.set(comfyuiWorkflows, forKey: Keys.comfyuiWorkflows) }
    }

    /// Per-workflow values for the `%name%` markers a workflow exposes:
    /// `[workflowName: [paramName: value]]`. A `seed` value that isn't a
    /// number means "randomise each run". Absent entries fall back to the
    /// marker's inline default.
    var comfyuiWorkflowParams: [String: [String: String]] {
        didSet { defaults.set(comfyuiWorkflowParams, forKey: Keys.comfyuiWorkflowParams) }
    }

    func comfyuiParams(for workflow: String) -> [String: String] {
        comfyuiWorkflowParams[workflow] ?? [:]
    }

    func setComfyuiParam(_ value: String, name: String, for workflow: String) {
        var values = comfyuiWorkflowParams[workflow] ?? [:]
        values[name] = value
        comfyuiWorkflowParams[workflow] = values
    }

    var comfyuiBaseURL: URL? {
        let trimmed = comfyuiBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }

    /// Adds or replaces a named workflow. Selects it as active when none is.
    func addComfyUIWorkflow(name: String, json: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        comfyuiWorkflows[name] = json
        if comfyuiModel == nil { comfyuiModel = name }
    }

    /// Drops a workflow, moving the active selection off it if needed.
    func removeComfyUIWorkflow(name: String) {
        comfyuiWorkflows[name] = nil
        comfyuiWorkflowParams[name] = nil
        if comfyuiModel == name { comfyuiModel = comfyuiWorkflows.keys.sorted().first }
    }

    // MARK: - Per-provider catalogs

    var anthropicCatalog: [String] = [] {
        didSet { defaults.set(anthropicCatalog, forKey: Keys.catalog(.anthropic)) }
    }

    var deepseekCatalog: [String] = [] {
        didSet { defaults.set(deepseekCatalog, forKey: Keys.catalog(.deepseek)) }
    }

    var googleCatalog: [String] = [] {
        didSet { defaults.set(googleCatalog, forKey: Keys.catalog(.google)) }
    }

    var localOpenAICatalog: [String] = [] {
        didSet { defaults.set(localOpenAICatalog, forKey: Keys.catalog(.localOpenAI)) }
    }

    var mistralCatalog: [String] = [] {
        didSet { defaults.set(mistralCatalog, forKey: Keys.catalog(.mistral)) }
    }

    var ollamaCatalog: [String] = [] {
        didSet { defaults.set(ollamaCatalog, forKey: Keys.catalog(.ollama)) }
    }

    var openaiCatalog: [String] = [] {
        didSet { defaults.set(openaiCatalog, forKey: Keys.catalog(.openai)) }
    }

    var qwenCatalog: [String] = [] {
        didSet { defaults.set(qwenCatalog, forKey: Keys.catalog(.qwen)) }
    }

    var zaiCatalog: [String] = [] {
        didSet { defaults.set(zaiCatalog, forKey: Keys.catalog(.zai)) }
    }

    func catalog(for provider: ProviderID) -> [String] {
        switch provider {
        case .anthropic:    return anthropicCatalog
        case .apple:        return []
        case .comfyui:      return comfyuiWorkflows.keys.sorted()
        case .deepseek:     return deepseekCatalog
        case .google:       return googleCatalog
        case .localOpenAI:  return localOpenAICatalog
        case .mistral:      return mistralCatalog
        case .mlx:          return []
        case .ollama:       return ollamaCatalog
        case .openai:       return openaiCatalog
        case .qwen:         return qwenCatalog
        case .zai:          return zaiCatalog
        }
    }

    func setCatalog(_ ids: [String], for provider: ProviderID) {
        // Some providers' /models endpoints list ids more than once (Mistral
        // notably); store each at most once, preserving order.
        var seen = Set<String>()
        let ids = ids.filter { seen.insert($0).inserted }
        switch provider {
        case .anthropic:    anthropicCatalog = ids
        case .apple:        break
        case .comfyui:      break   // workflows are managed directly, not fetched
        case .deepseek:     deepseekCatalog = ids
        case .google:       googleCatalog = ids
        case .localOpenAI:  localOpenAICatalog = ids
        case .mistral:      mistralCatalog = ids
        case .mlx:          break
        case .ollama:       ollamaCatalog = ids
        case .openai:       openaiCatalog = ids
        case .qwen:         qwenCatalog = ids
        case .zai:          zaiCatalog = ids
        }
        // Prune previously-enabled models that no longer exist in the
        // catalog (the provider deprecated them, the user changed account,
        // etc.). Keeps the picker honest. The active-model constraint runs
        // implicitly via setEnabled.
        let fresh = Set(ids)
        let stale = enabledModels(for: provider).subtracting(fresh)
        for modelID in stale {
            setEnabled(false, modelID: modelID, for: provider)
        }
    }

    // MARK: - Per-provider enabled models

    var enabledAnthropicModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledAnthropicModels), forKey: Keys.enabledModels(for: .anthropic)) }
    }

    var enabledDeepSeekModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledDeepSeekModels), forKey: Keys.enabledModels(for: .deepseek)) }
    }

    var enabledGoogleModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledGoogleModels), forKey: Keys.enabledModels(for: .google)) }
    }

    var enabledLocalOpenAIModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledLocalOpenAIModels), forKey: Keys.enabledModels(for: .localOpenAI)) }
    }

    var enabledMistralModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledMistralModels), forKey: Keys.enabledModels(for: .mistral)) }
    }

    var enabledOllamaModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledOllamaModels), forKey: Keys.enabledModels(for: .ollama)) }
    }

    var enabledOpenAIModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledOpenAIModels), forKey: Keys.enabledModels(for: .openai)) }
    }

    var enabledQwenModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledQwenModels), forKey: Keys.enabledModels(for: .qwen)) }
    }

    var enabledZAIModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledZAIModels), forKey: Keys.enabledModels(for: .zai)) }
    }

    func enabledModels(for provider: ProviderID) -> Set<String> {
        switch provider {
        case .anthropic:    return enabledAnthropicModels
        case .apple:        return []
        case .comfyui:      return Set(comfyuiWorkflows.keys)
        case .deepseek:     return enabledDeepSeekModels
        case .google:       return enabledGoogleModels
        case .localOpenAI:  return enabledLocalOpenAIModels
        case .mistral:      return enabledMistralModels
        case .mlx:          return []
        case .ollama:       return enabledOllamaModels
        case .openai:       return enabledOpenAIModels
        case .qwen:         return enabledQwenModels
        case .zai:          return enabledZAIModels
        }
    }

    func setEnabled(_ enabled: Bool, modelID: String, for provider: ProviderID) {
        switch provider {
        case .anthropic:
            if enabled { enabledAnthropicModels.insert(modelID) } else { enabledAnthropicModels.remove(modelID) }
            constrainActive(&anthropicModel, to: enabledAnthropicModels)
        case .apple:
            break
        case .comfyui:
            // Enabling needs the workflow JSON (added via the settings view);
            // only removal is meaningful here.
            if !enabled { removeComfyUIWorkflow(name: modelID) }
        case .deepseek:
            if enabled { enabledDeepSeekModels.insert(modelID) } else { enabledDeepSeekModels.remove(modelID) }
            constrainActive(&deepseekModel, to: enabledDeepSeekModels)
        case .google:
            if enabled { enabledGoogleModels.insert(modelID) } else { enabledGoogleModels.remove(modelID) }
            constrainActive(&googleModel, to: enabledGoogleModels)
        case .localOpenAI:
            if enabled { enabledLocalOpenAIModels.insert(modelID) } else { enabledLocalOpenAIModels.remove(modelID) }
            constrainActive(&localOpenAIModel, to: enabledLocalOpenAIModels)
        case .mlx:
            // No chat catalog yet; Phase C wires this when MLX
            // chat lands.
            break
        case .mistral:
            if enabled { enabledMistralModels.insert(modelID) } else { enabledMistralModels.remove(modelID) }
            constrainActive(&mistralModel, to: enabledMistralModels)
        case .ollama:
            if enabled { enabledOllamaModels.insert(modelID) } else { enabledOllamaModels.remove(modelID) }
            constrainActive(&selectedModel, to: enabledOllamaModels)
        case .openai:
            if enabled { enabledOpenAIModels.insert(modelID) } else { enabledOpenAIModels.remove(modelID) }
            constrainActive(&openaiModel, to: enabledOpenAIModels)
        case .qwen:
            if enabled { enabledQwenModels.insert(modelID) } else { enabledQwenModels.remove(modelID) }
            constrainActive(&qwenModel, to: enabledQwenModels)
        case .zai:
            if enabled { enabledZAIModels.insert(modelID) } else { enabledZAIModels.remove(modelID) }
            constrainActive(&zaiModel, to: enabledZAIModels)
        }
    }

    private func constrainActive(_ active: inout String?, to enabled: Set<String>) {
        if let m = active, !enabled.contains(m) {
            active = enabled.sorted().first
        }
    }

    // MARK: - Tools

    /// Tools the user has switched off. Stored as the disabled set so any new
    /// built-in tool is enabled by default.
    var disabledTools: Set<String> = [] {
        didSet { defaults.set(Array(disabledTools), forKey: Keys.disabledTools) }
    }

    /// Tools the user has explicitly enabled for Apple Intelligence. Stored
    /// as the *enabled* set (the opposite of `disabledTools`) because the
    /// on-device model's 4k-token context fills up fast — defaulting to none
    /// keeps the provider usable for plain chat until the user opts in to
    /// specific tools.
    var appleEnabledTools: Set<String> = [] {
        didSet { defaults.set(Array(appleEnabledTools), forKey: Keys.appleEnabledTools) }
    }

    /// Brave Search API subscription token, backing the `web_search` tool.
    var braveAPIKey: String {
        didSet { KeychainStore.set(braveAPIKey, account: KeychainAccounts.braveAPIKey) }
    }

    // MARK: - Wiki LLM (Phase 7+)

    /// Master switch — when false the 6 wiki tools aren't exposed to
    /// any provider, the index DB stays untouched, no file-watcher.
    var wikiEnabled: Bool {
        didSet { defaults.set(wikiEnabled, forKey: Keys.wikiEnabled) }
    }

    /// Injects the wiki preamble (conventions + catalog + behavioral
    /// instructions) as system context on each send. On by default —
    /// it's what makes the model actually use the wiki.
    var wikiContextEnabled: Bool {
        didSet { defaults.set(wikiContextEnabled, forKey: Keys.wikiContextEnabled) }
    }

    /// When on, the model enriches the wiki on its own as you chat. Off by
    /// default: writes are deliberate (explicit request or the "Wikifier"
    /// action), so you choose what gets saved. Reading the wiki to answer
    /// is always on.
    var wikiAutoCuration: Bool {
        didSet { defaults.set(wikiAutoCuration, forKey: Keys.wikiAutoCuration) }
    }

    /// Embedding model name used at the Ollama side (e.g. `bge-m3`,
    /// `nomic-embed-text`). Locked to the dimension stamped in the DB
    /// at first open — changing the dim mid-flight requires a
    /// rebuild-vectoriel migration.
    var wikiEmbeddingModelID: String {
        didSet { defaults.set(wikiEmbeddingModelID, forKey: Keys.wikiEmbeddingModelID) }
    }

    /// Dimension of the embedding vectors. Set once at first DB
    /// creation. Surface in settings so the user can pick the right
    /// value for their chosen model (bge-m3 = 1024, nomic = 768).
    var wikiEmbeddingDimension: Int {
        didSet { defaults.set(wikiEmbeddingDimension, forKey: Keys.wikiEmbeddingDimension) }
    }

    /// Which provider serves embeddings to the indexer + finder:
    /// "ollama" (default) reuses `serverURL`; "mlx" runs bge-m3 in-process
    /// on Apple Silicon (no URL). The wiki itself stays the same — only the
    /// request URL changes.
    var wikiEmbeddingProviderID: String {
        didSet { defaults.set(wikiEmbeddingProviderID, forKey: Keys.wikiEmbeddingProviderID) }
    }

    /// Cap (in gigabytes) for the MLX model cache. The launch GC
    /// pass evicts least-recently-used models until the total drops
    /// under this number. 10 GB by default — covers bge-m3-4bit +
    /// Llama-3.2-3B-4bit (Phase C) with headroom.
    var mlxCacheCapGB: Double {
        didSet { defaults.set(mlxCacheCapGB, forKey: Keys.mlxCacheCapGB) }
    }

    /// The HuggingFace slug of the currently-selected MLX chat
    /// model. `nil` means the picker hasn't been touched yet.
    var mlxChatModelID: String? {
        didSet { defaults.set(mlxChatModelID, forKey: Keys.mlxChatModelID) }
    }

    /// HuggingFace slugs the user added by hand (chat models outside
    /// the curated catalog, e.g. `mlx-community/gpt-oss-20b-MXFP4-Q4`).
    /// Persisted so they survive cache eviction and surface in the
    /// model picker once downloaded.
    var mlxCustomChatModelIDs: [String] {
        didSet { defaults.set(mlxCustomChatModelIDs, forKey: Keys.mlxCustomChatModelIDs) }
    }

    /// Registers a hand-typed MLX chat model slug. Trims whitespace
    /// and ignores empties / duplicates. Returns the normalised slug
    /// when it was added (so the caller can kick off a download), or
    /// `nil` otherwise.
    @discardableResult
    func addCustomMLXChatModel(_ id: String) -> String? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !mlxCustomChatModelIDs.contains(trimmed) else { return nil }
        mlxCustomChatModelIDs.append(trimmed)
        return trimmed
    }

    /// Drops a hand-typed MLX chat model slug, clearing the active
    /// selection if it pointed at it.
    func removeCustomMLXChatModel(_ id: String) {
        mlxCustomChatModelIDs.removeAll { $0 == id }
        if mlxChatModelID == id { mlxChatModelID = nil }
    }

    func isToolEnabled(_ name: String) -> Bool {
        !disabledTools.contains(name)
    }

    func setToolEnabled(_ enabled: Bool, name: String) {
        if enabled { disabledTools.remove(name) } else { disabledTools.insert(name) }
    }

    func isAppleToolEnabled(_ name: String) -> Bool {
        appleEnabledTools.contains(name)
    }

    func setAppleToolEnabled(_ enabled: Bool, name: String) {
        if enabled { appleEnabledTools.insert(name) } else { appleEnabledTools.remove(name) }
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedProviderID = defaults.string(forKey: Keys.selectedProvider) ?? "ollama"
        self.anthropicAPIKey = KeychainStore.get(account: KeychainAccounts.anthropicAPIKey) ?? ""
        self.anthropicModel = defaults.string(forKey: Keys.anthropicModel)
        self.deepseekAPIKey = KeychainStore.get(account: KeychainAccounts.deepseekAPIKey) ?? ""
        self.deepseekModel = defaults.string(forKey: Keys.deepseekModel)
        self.googleAPIKey = KeychainStore.get(account: KeychainAccounts.googleAPIKey) ?? ""
        self.googleModel = defaults.string(forKey: Keys.googleModel)
        self.localOpenAIBaseURLString = defaults.string(forKey: Keys.localOpenAIBaseURL) ?? ""
        self.localOpenAIAPIKey = KeychainStore.get(account: KeychainAccounts.localOpenAIAPIKey) ?? ""
        self.localOpenAIModel = defaults.string(forKey: Keys.localOpenAIModel)
        self.mistralAPIKey = KeychainStore.get(account: KeychainAccounts.mistralAPIKey) ?? ""
        self.mistralModel = defaults.string(forKey: Keys.mistralModel)
        self.serverURLString = defaults.string(forKey: Keys.serverURL) ?? "http://localhost:11434"
        self.selectedModel = defaults.string(forKey: Keys.selectedModel)
        self.openaiAPIKey = KeychainStore.get(account: KeychainAccounts.openaiAPIKey) ?? ""
        self.openaiModel = defaults.string(forKey: Keys.openaiModel)
        self.qwenAPIKey = KeychainStore.get(account: KeychainAccounts.qwenAPIKey) ?? ""
        self.qwenModel = defaults.string(forKey: Keys.qwenModel)
        self.zaiAPIKey = KeychainStore.get(account: KeychainAccounts.zaiAPIKey) ?? ""
        self.zaiModel = defaults.string(forKey: Keys.zaiModel)
        self.comfyuiBaseURLString = defaults.string(forKey: Keys.comfyuiBaseURL) ?? "http://localhost:8188"
        self.comfyuiAPIKey = KeychainStore.get(account: KeychainAccounts.comfyuiAPIKey) ?? ""
        self.comfyuiModel = defaults.string(forKey: Keys.comfyuiModel)
        self.comfyuiWorkflows = defaults.dictionary(forKey: Keys.comfyuiWorkflows) as? [String: String] ?? [:]
        self.comfyuiWorkflowParams = defaults.dictionary(forKey: Keys.comfyuiWorkflowParams) as? [String: [String: String]] ?? [:]
        self.anthropicCatalog = defaults.array(forKey: Keys.catalog(.anthropic)) as? [String] ?? []
        self.deepseekCatalog = defaults.array(forKey: Keys.catalog(.deepseek)) as? [String] ?? []
        self.googleCatalog = defaults.array(forKey: Keys.catalog(.google)) as? [String] ?? []
        self.localOpenAICatalog = defaults.array(forKey: Keys.catalog(.localOpenAI)) as? [String] ?? []
        self.mistralCatalog = defaults.array(forKey: Keys.catalog(.mistral)) as? [String] ?? []
        self.ollamaCatalog = defaults.array(forKey: Keys.catalog(.ollama)) as? [String] ?? []
        self.openaiCatalog = defaults.array(forKey: Keys.catalog(.openai)) as? [String] ?? []
        self.qwenCatalog = defaults.array(forKey: Keys.catalog(.qwen)) as? [String] ?? []
        self.zaiCatalog = defaults.array(forKey: Keys.catalog(.zai)) as? [String] ?? []
        self.enabledAnthropicModels = Set(defaults.array(forKey: Keys.enabledModels(for: .anthropic)) as? [String] ?? [])
        self.enabledDeepSeekModels = Set(defaults.array(forKey: Keys.enabledModels(for: .deepseek)) as? [String] ?? [])
        self.enabledGoogleModels = Set(defaults.array(forKey: Keys.enabledModels(for: .google)) as? [String] ?? [])
        self.enabledLocalOpenAIModels = Set(defaults.array(forKey: Keys.enabledModels(for: .localOpenAI)) as? [String] ?? [])
        self.enabledMistralModels = Set(defaults.array(forKey: Keys.enabledModels(for: .mistral)) as? [String] ?? [])
        self.enabledOllamaModels = Set(defaults.array(forKey: Keys.enabledModels(for: .ollama)) as? [String] ?? [])
        self.enabledOpenAIModels = Set(defaults.array(forKey: Keys.enabledModels(for: .openai)) as? [String] ?? [])
        self.enabledQwenModels = Set(defaults.array(forKey: Keys.enabledModels(for: .qwen)) as? [String] ?? [])
        self.enabledZAIModels = Set(defaults.array(forKey: Keys.enabledModels(for: .zai)) as? [String] ?? [])
        self.disabledTools = Set(defaults.array(forKey: Keys.disabledTools) as? [String] ?? [])
        self.appleEnabledTools = Set(defaults.array(forKey: Keys.appleEnabledTools) as? [String] ?? [])
        self.braveAPIKey = KeychainStore.get(account: KeychainAccounts.braveAPIKey) ?? ""
        self.wikiEnabled = defaults.bool(forKey: Keys.wikiEnabled)
        // Default-true: absent key means enabled.
        self.wikiContextEnabled = defaults.object(forKey: Keys.wikiContextEnabled) as? Bool ?? true
        self.wikiAutoCuration = defaults.bool(forKey: Keys.wikiAutoCuration)
        self.wikiEmbeddingModelID = defaults.string(forKey: Keys.wikiEmbeddingModelID) ?? "nomic-embed-text"
        let storedDim = defaults.integer(forKey: Keys.wikiEmbeddingDimension)
        self.wikiEmbeddingDimension = storedDim > 0 ? storedDim : 768
        // "localOpenAI" was a removed embedder option. Coerce stale values
        // back to Ollama so the segmented picker has a matching tag and the
        // indexer falls on a working provider.
        let storedEmbeddingProvider = defaults.string(forKey: Keys.wikiEmbeddingProviderID) ?? "ollama"
        self.wikiEmbeddingProviderID = storedEmbeddingProvider == "localOpenAI" ? "ollama" : storedEmbeddingProvider
        let storedCap = defaults.double(forKey: Keys.mlxCacheCapGB)
        self.mlxCacheCapGB = storedCap > 0 ? storedCap : 10
        self.mlxChatModelID = defaults.string(forKey: Keys.mlxChatModelID)
        self.mlxCustomChatModelIDs = defaults.stringArray(forKey: Keys.mlxCustomChatModelIDs) ?? []
    }

    private enum Keys {
        static let selectedProvider = "providers.selected"
        static let serverURL = "ollama.serverURL"
        static let selectedModel = "ollama.selectedModel"
        static let anthropicModel = "anthropic.selectedModel"
        static let deepseekModel = "deepseek.selectedModel"
        static let googleModel = "google.selectedModel"
        static let localOpenAIBaseURL = "localOpenAI.baseURL"
        static let localOpenAIModel = "localOpenAI.selectedModel"
        static let mistralModel = "mistral.selectedModel"
        static let openaiModel = "openai.selectedModel"
        static let qwenModel = "qwen.selectedModel"
        static let zaiModel = "zai.selectedModel"
        static let comfyuiBaseURL = "comfyui.baseURL"
        static let comfyuiModel = "comfyui.selectedModel"
        static let comfyuiWorkflows = "comfyui.workflows"
        static let comfyuiWorkflowParams = "comfyui.workflowParams"
        static let disabledTools = "tools.disabled"
        static let appleEnabledTools = "tools.apple.enabled"
        static let wikiEnabled = "wiki.enabled"
        static let wikiContextEnabled = "wiki.contextEnabled"
        static let wikiAutoCuration = "wiki.autoCuration"
        static let wikiEmbeddingModelID = "wiki.embeddingModelID"
        static let wikiEmbeddingDimension = "wiki.embeddingDimension"
        static let wikiEmbeddingProviderID = "wiki.embeddingProviderID"
        static let mlxCacheCapGB = "mlx.cacheCapGB"
        static let mlxChatModelID = "mlx.chatModelID"
        static let mlxCustomChatModelIDs = "mlx.customChatModelIDs"

        static func enabledModels(for provider: ProviderID) -> String {
            "enabled.\(provider.rawValue)"
        }
        static func catalog(_ provider: ProviderID) -> String {
            "catalog.\(provider.rawValue)"
        }
    }

    private enum KeychainAccounts {
        static let anthropicAPIKey = "anthropic.apiKey"
        static let deepseekAPIKey = "deepseek.apiKey"
        static let googleAPIKey = "google.apiKey"
        static let localOpenAIAPIKey = "localOpenAI.apiKey"
        static let mistralAPIKey = "mistral.apiKey"
        static let openaiAPIKey = "openai.apiKey"
        static let qwenAPIKey = "qwen.apiKey"
        static let zaiAPIKey = "zai.apiKey"
        static let comfyuiAPIKey = "comfyui.apiKey"
        static let braveAPIKey = "brave.apiKey"
    }
}
