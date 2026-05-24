import Foundation
import Observation

@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.serverURLString = defaults.string(forKey: Keys.serverURL) ?? "http://localhost:11434"
        self.selectedModel = defaults.string(forKey: Keys.selectedModel)
    }

    private enum Keys {
        static let serverURL = "ollama.serverURL"
        static let selectedModel = "ollama.selectedModel"
    }
}
