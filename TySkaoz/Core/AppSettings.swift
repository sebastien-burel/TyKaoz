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

    /// Backed by Keychain.
    var mistralAPIKey: String {
        didSet { KeychainStore.set(mistralAPIKey, account: KeychainAccounts.mistralAPIKey) }
    }

    var mistralModel: String? {
        didSet { defaults.set(mistralModel, forKey: Keys.mistralModel) }
    }

    // MARK: - Per-provider catalogs (raw lists from the last "Test")
    // Observable + persisted so that switching provider panels doesn't lose
    // the catalog and a relaunch keeps the last fetched list.

    var ollamaCatalog: [String] = [] {
        didSet { defaults.set(ollamaCatalog, forKey: Keys.catalog(.ollama)) }
    }

    var mistralCatalog: [String] = [] {
        didSet { defaults.set(mistralCatalog, forKey: Keys.catalog(.mistral)) }
    }

    func catalog(for provider: ProviderID) -> [String] {
        switch provider {
        case .ollama:  return ollamaCatalog
        case .mistral: return mistralCatalog
        case .apple:   return []
        }
    }

    func setCatalog(_ ids: [String], for provider: ProviderID) {
        switch provider {
        case .ollama:  ollamaCatalog = ids
        case .mistral: mistralCatalog = ids
        case .apple:   break
        }
    }

    // MARK: - Per-provider enabled models

    /// Observable stored properties (so SwiftUI re-renders on mutation) +
    /// persistence in didSet.
    var enabledOllamaModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledOllamaModels), forKey: Keys.enabledModels(for: .ollama)) }
    }

    var enabledMistralModels: Set<String> = [] {
        didSet { defaults.set(Array(enabledMistralModels), forKey: Keys.enabledModels(for: .mistral)) }
    }

    func enabledModels(for provider: ProviderID) -> Set<String> {
        switch provider {
        case .ollama:  return enabledOllamaModels
        case .mistral: return enabledMistralModels
        case .apple:   return []
        }
    }

    func setEnabled(_ enabled: Bool, modelID: String, for provider: ProviderID) {
        switch provider {
        case .ollama:
            if enabled { enabledOllamaModels.insert(modelID) } else { enabledOllamaModels.remove(modelID) }
            if let m = selectedModel, !enabledOllamaModels.contains(m) {
                selectedModel = enabledOllamaModels.sorted().first
            }
        case .mistral:
            if enabled { enabledMistralModels.insert(modelID) } else { enabledMistralModels.remove(modelID) }
            if let m = mistralModel, !enabledMistralModels.contains(m) {
                mistralModel = enabledMistralModels.sorted().first
            }
        case .apple:
            break
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
        self.ollamaCatalog = defaults.array(forKey: Keys.catalog(.ollama)) as? [String] ?? []
        self.mistralCatalog = defaults.array(forKey: Keys.catalog(.mistral)) as? [String] ?? []
        self.enabledOllamaModels = Set(defaults.array(forKey: Keys.enabledModels(for: .ollama)) as? [String] ?? [])
        self.enabledMistralModels = Set(defaults.array(forKey: Keys.enabledModels(for: .mistral)) as? [String] ?? [])
    }

    private enum Keys {
        static let selectedProvider = "providers.selected"
        static let serverURL = "ollama.serverURL"
        static let selectedModel = "ollama.selectedModel"
        static let mistralModel = "mistral.selectedModel"

        static func enabledModels(for provider: ProviderID) -> String {
            "enabled.\(provider.rawValue)"
        }
        static func catalog(_ provider: ProviderID) -> String {
            "catalog.\(provider.rawValue)"
        }
    }

    private enum KeychainAccounts {
        static let mistralAPIKey = "mistral.apiKey"
    }
}
