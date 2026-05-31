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
        case .anthropic: return anthropicCatalog
        case .apple:     return []
        case .deepseek:  return deepseekCatalog
        case .google:    return googleCatalog
        case .mistral:   return mistralCatalog
        case .ollama:    return ollamaCatalog
        case .openai:    return openaiCatalog
        case .qwen:      return qwenCatalog
        case .zai:       return zaiCatalog
        }
    }

    func setCatalog(_ ids: [String], for provider: ProviderID) {
        switch provider {
        case .anthropic: anthropicCatalog = ids
        case .apple:     break
        case .deepseek:  deepseekCatalog = ids
        case .google:    googleCatalog = ids
        case .mistral:   mistralCatalog = ids
        case .ollama:    ollamaCatalog = ids
        case .openai:    openaiCatalog = ids
        case .qwen:      qwenCatalog = ids
        case .zai:       zaiCatalog = ids
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
        case .anthropic: return enabledAnthropicModels
        case .apple:     return []
        case .deepseek:  return enabledDeepSeekModels
        case .google:    return enabledGoogleModels
        case .mistral:   return enabledMistralModels
        case .ollama:    return enabledOllamaModels
        case .openai:    return enabledOpenAIModels
        case .qwen:      return enabledQwenModels
        case .zai:       return enabledZAIModels
        }
    }

    func setEnabled(_ enabled: Bool, modelID: String, for provider: ProviderID) {
        switch provider {
        case .anthropic:
            if enabled { enabledAnthropicModels.insert(modelID) } else { enabledAnthropicModels.remove(modelID) }
            constrainActive(&anthropicModel, to: enabledAnthropicModels)
        case .apple:
            break
        case .deepseek:
            if enabled { enabledDeepSeekModels.insert(modelID) } else { enabledDeepSeekModels.remove(modelID) }
            constrainActive(&deepseekModel, to: enabledDeepSeekModels)
        case .google:
            if enabled { enabledGoogleModels.insert(modelID) } else { enabledGoogleModels.remove(modelID) }
            constrainActive(&googleModel, to: enabledGoogleModels)
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

    /// Brave Search API subscription token, backing the `web_search` tool.
    var braveAPIKey: String {
        didSet { KeychainStore.set(braveAPIKey, account: KeychainAccounts.braveAPIKey) }
    }

    func isToolEnabled(_ name: String) -> Bool {
        !disabledTools.contains(name)
    }

    func setToolEnabled(_ enabled: Bool, name: String) {
        if enabled { disabledTools.remove(name) } else { disabledTools.insert(name) }
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
        self.anthropicCatalog = defaults.array(forKey: Keys.catalog(.anthropic)) as? [String] ?? []
        self.deepseekCatalog = defaults.array(forKey: Keys.catalog(.deepseek)) as? [String] ?? []
        self.googleCatalog = defaults.array(forKey: Keys.catalog(.google)) as? [String] ?? []
        self.mistralCatalog = defaults.array(forKey: Keys.catalog(.mistral)) as? [String] ?? []
        self.ollamaCatalog = defaults.array(forKey: Keys.catalog(.ollama)) as? [String] ?? []
        self.openaiCatalog = defaults.array(forKey: Keys.catalog(.openai)) as? [String] ?? []
        self.qwenCatalog = defaults.array(forKey: Keys.catalog(.qwen)) as? [String] ?? []
        self.zaiCatalog = defaults.array(forKey: Keys.catalog(.zai)) as? [String] ?? []
        self.enabledAnthropicModels = Set(defaults.array(forKey: Keys.enabledModels(for: .anthropic)) as? [String] ?? [])
        self.enabledDeepSeekModels = Set(defaults.array(forKey: Keys.enabledModels(for: .deepseek)) as? [String] ?? [])
        self.enabledGoogleModels = Set(defaults.array(forKey: Keys.enabledModels(for: .google)) as? [String] ?? [])
        self.enabledMistralModels = Set(defaults.array(forKey: Keys.enabledModels(for: .mistral)) as? [String] ?? [])
        self.enabledOllamaModels = Set(defaults.array(forKey: Keys.enabledModels(for: .ollama)) as? [String] ?? [])
        self.enabledOpenAIModels = Set(defaults.array(forKey: Keys.enabledModels(for: .openai)) as? [String] ?? [])
        self.enabledQwenModels = Set(defaults.array(forKey: Keys.enabledModels(for: .qwen)) as? [String] ?? [])
        self.enabledZAIModels = Set(defaults.array(forKey: Keys.enabledModels(for: .zai)) as? [String] ?? [])
        self.disabledTools = Set(defaults.array(forKey: Keys.disabledTools) as? [String] ?? [])
        self.braveAPIKey = KeychainStore.get(account: KeychainAccounts.braveAPIKey) ?? ""
    }

    private enum Keys {
        static let selectedProvider = "providers.selected"
        static let serverURL = "ollama.serverURL"
        static let selectedModel = "ollama.selectedModel"
        static let anthropicModel = "anthropic.selectedModel"
        static let deepseekModel = "deepseek.selectedModel"
        static let googleModel = "google.selectedModel"
        static let mistralModel = "mistral.selectedModel"
        static let openaiModel = "openai.selectedModel"
        static let qwenModel = "qwen.selectedModel"
        static let zaiModel = "zai.selectedModel"
        static let disabledTools = "tools.disabled"

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
        static let mistralAPIKey = "mistral.apiKey"
        static let openaiAPIKey = "openai.apiKey"
        static let qwenAPIKey = "qwen.apiKey"
        static let zaiAPIKey = "zai.apiKey"
        static let braveAPIKey = "brave.apiKey"
    }
}
