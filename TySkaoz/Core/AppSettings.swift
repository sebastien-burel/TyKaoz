import Foundation
import Observation

@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var selectedProviderID: String {
        didSet { defaults.set(selectedProviderID, forKey: Keys.selectedProvider) }
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

    // MARK: - Mistral

    var mistralAPIKey: String {
        didSet { KeychainStore.set(mistralAPIKey, account: KeychainAccounts.mistralAPIKey) }
    }

    var mistralModel: String? {
        didSet { defaults.set(mistralModel, forKey: Keys.mistralModel) }
    }

    // MARK: - OpenAI

    var openaiAPIKey: String {
        didSet { KeychainStore.set(openaiAPIKey, account: KeychainAccounts.openaiAPIKey) }
    }

    var openaiModel: String? {
        didSet { defaults.set(openaiModel, forKey: Keys.openaiModel) }
    }

    // MARK: - Anthropic

    var anthropicAPIKey: String {
        didSet { KeychainStore.set(anthropicAPIKey, account: KeychainAccounts.anthropicAPIKey) }
    }

    var anthropicModel: String? {
        didSet { defaults.set(anthropicModel, forKey: Keys.anthropicModel) }
    }

    // MARK: - Google

    var googleAPIKey: String {
        didSet { KeychainStore.set(googleAPIKey, account: KeychainAccounts.googleAPIKey) }
    }

    var googleModel: String? {
        didSet { defaults.set(googleModel, forKey: Keys.googleModel) }
    }

    // MARK: - DeepSeek

    var deepseekAPIKey: String {
        didSet { KeychainStore.set(deepseekAPIKey, account: KeychainAccounts.deepseekAPIKey) }
    }

    var deepseekModel: String? {
        didSet { defaults.set(deepseekModel, forKey: Keys.deepseekModel) }
    }

    // MARK: - Per-provider catalogs

    var ollamaCatalog: [String] = [] {
        didSet { defaults.set(ollamaCatalog, forKey: Keys.catalog(.ollama)) }
    }

    var mistralCatalog: [String] = [] {
        didSet { defaults.set(mistralCatalog, forKey: Keys.catalog(.mistral)) }
    }

    var openaiCatalog: [String] = [] {
        didSet { defaults.set(openaiCatalog, forKey: Keys.catalog(.openai)) }
    }

    var anthropicCatalog: [String] = [] {
        didSet { defaults.set(anthropicCatalog, forKey: Keys.catalog(.anthropic)) }
    }

    var googleCatalog: [String] = [] {
        didSet { defaults.set(googleCatalog, forKey: Keys.catalog(.google)) }
    }

    var deepseekCatalog: [String] = [] {
        didSet { defaults.set(deepseekCatalog, forKey: Keys.catalog(.deepseek)) }
    }

    func catalog(for provider: ProviderID) -> [String] {
        switch provider {
        case .ollama:    return ollamaCatalog
        case .mistral:   return mistralCatalog
        case .openai:    return openaiCatalog
        case .anthropic: return anthropicCatalog
        case .google:    return googleCatalog
        case .deepseek:  return deepseekCatalog
        case .apple:     return []
        }
    }

    func setCatalog(_ ids: [String], for provider: ProviderID) {
        switch provider {
        case .ollama:    ollamaCatalog = ids
        case .mistral:   mistralCatalog = ids
        case .openai:    openaiCatalog = ids
        case .anthropic: anthropicCatalog = ids
        case .google:    googleCatalog = ids
        case .deepseek:  deepseekCatalog = ids
        case .apple:     break
        }
    }

    // MARK: - Per-provider enabled models

    var enabledOllamaModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledOllamaModels), forKey: Keys.enabledModels(for: .ollama)) }
    }

    var enabledMistralModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledMistralModels), forKey: Keys.enabledModels(for: .mistral)) }
    }

    var enabledOpenAIModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledOpenAIModels), forKey: Keys.enabledModels(for: .openai)) }
    }

    var enabledAnthropicModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledAnthropicModels), forKey: Keys.enabledModels(for: .anthropic)) }
    }

    var enabledGoogleModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledGoogleModels), forKey: Keys.enabledModels(for: .google)) }
    }

    var enabledDeepSeekModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledDeepSeekModels), forKey: Keys.enabledModels(for: .deepseek)) }
    }

    func enabledModels(for provider: ProviderID) -> Set<String> {
        switch provider {
        case .ollama:    return enabledOllamaModels
        case .mistral:   return enabledMistralModels
        case .openai:    return enabledOpenAIModels
        case .anthropic: return enabledAnthropicModels
        case .google:    return enabledGoogleModels
        case .deepseek:  return enabledDeepSeekModels
        case .apple:     return []
        }
    }

    func setEnabled(_ enabled: Bool, modelID: String, for provider: ProviderID) {
        switch provider {
        case .ollama:
            if enabled { enabledOllamaModels.insert(modelID) } else { enabledOllamaModels.remove(modelID) }
            constrainActive(&selectedModel, to: enabledOllamaModels)
        case .mistral:
            if enabled { enabledMistralModels.insert(modelID) } else { enabledMistralModels.remove(modelID) }
            constrainActive(&mistralModel, to: enabledMistralModels)
        case .openai:
            if enabled { enabledOpenAIModels.insert(modelID) } else { enabledOpenAIModels.remove(modelID) }
            constrainActive(&openaiModel, to: enabledOpenAIModels)
        case .anthropic:
            if enabled { enabledAnthropicModels.insert(modelID) } else { enabledAnthropicModels.remove(modelID) }
            constrainActive(&anthropicModel, to: enabledAnthropicModels)
        case .google:
            if enabled { enabledGoogleModels.insert(modelID) } else { enabledGoogleModels.remove(modelID) }
            constrainActive(&googleModel, to: enabledGoogleModels)
        case .deepseek:
            if enabled { enabledDeepSeekModels.insert(modelID) } else { enabledDeepSeekModels.remove(modelID) }
            constrainActive(&deepseekModel, to: enabledDeepSeekModels)
        case .apple:
            break
        }
    }

    private func constrainActive(_ active: inout String?, to enabled: Set<String>) {
        if let m = active, !enabled.contains(m) {
            active = enabled.sorted().first
        }
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedProviderID = defaults.string(forKey: Keys.selectedProvider) ?? "ollama"
        self.serverURLString = defaults.string(forKey: Keys.serverURL) ?? "http://localhost:11434"
        self.selectedModel = defaults.string(forKey: Keys.selectedModel)
        self.mistralAPIKey = KeychainStore.get(account: KeychainAccounts.mistralAPIKey) ?? ""
        self.mistralModel = defaults.string(forKey: Keys.mistralModel)
        self.openaiAPIKey = KeychainStore.get(account: KeychainAccounts.openaiAPIKey) ?? ""
        self.openaiModel = defaults.string(forKey: Keys.openaiModel)
        self.anthropicAPIKey = KeychainStore.get(account: KeychainAccounts.anthropicAPIKey) ?? ""
        self.anthropicModel = defaults.string(forKey: Keys.anthropicModel)
        self.googleAPIKey = KeychainStore.get(account: KeychainAccounts.googleAPIKey) ?? ""
        self.googleModel = defaults.string(forKey: Keys.googleModel)
        self.deepseekAPIKey = KeychainStore.get(account: KeychainAccounts.deepseekAPIKey) ?? ""
        self.deepseekModel = defaults.string(forKey: Keys.deepseekModel)
        self.ollamaCatalog = defaults.array(forKey: Keys.catalog(.ollama)) as? [String] ?? []
        self.mistralCatalog = defaults.array(forKey: Keys.catalog(.mistral)) as? [String] ?? []
        self.openaiCatalog = defaults.array(forKey: Keys.catalog(.openai)) as? [String] ?? []
        self.anthropicCatalog = defaults.array(forKey: Keys.catalog(.anthropic)) as? [String] ?? []
        self.googleCatalog = defaults.array(forKey: Keys.catalog(.google)) as? [String] ?? []
        self.deepseekCatalog = defaults.array(forKey: Keys.catalog(.deepseek)) as? [String] ?? []
        self.enabledOllamaModels = Set(defaults.array(forKey: Keys.enabledModels(for: .ollama)) as? [String] ?? [])
        self.enabledMistralModels = Set(defaults.array(forKey: Keys.enabledModels(for: .mistral)) as? [String] ?? [])
        self.enabledOpenAIModels = Set(defaults.array(forKey: Keys.enabledModels(for: .openai)) as? [String] ?? [])
        self.enabledAnthropicModels = Set(defaults.array(forKey: Keys.enabledModels(for: .anthropic)) as? [String] ?? [])
        self.enabledGoogleModels = Set(defaults.array(forKey: Keys.enabledModels(for: .google)) as? [String] ?? [])
        self.enabledDeepSeekModels = Set(defaults.array(forKey: Keys.enabledModels(for: .deepseek)) as? [String] ?? [])
    }

    private enum Keys {
        static let selectedProvider = "providers.selected"
        static let serverURL = "ollama.serverURL"
        static let selectedModel = "ollama.selectedModel"
        static let mistralModel = "mistral.selectedModel"
        static let openaiModel = "openai.selectedModel"
        static let anthropicModel = "anthropic.selectedModel"
        static let googleModel = "google.selectedModel"
        static let deepseekModel = "deepseek.selectedModel"

        static func enabledModels(for provider: ProviderID) -> String {
            "enabled.\(provider.rawValue)"
        }
        static func catalog(_ provider: ProviderID) -> String {
            "catalog.\(provider.rawValue)"
        }
    }

    private enum KeychainAccounts {
        static let mistralAPIKey = "mistral.apiKey"
        static let openaiAPIKey = "openai.apiKey"
        static let anthropicAPIKey = "anthropic.apiKey"
        static let googleAPIKey = "google.apiKey"
        static let deepseekAPIKey = "deepseek.apiKey"
    }
}
