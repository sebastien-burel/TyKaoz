import Foundation
import Testing
@testable import TyKaoz

struct AppSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "TyKaoz.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func defaultsToLocalhostOllama() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.serverURLString == "http://localhost:11434")
        #expect(settings.selectedModel == nil)
    }

    @Test
    func computedURLRejectsEmptyAndSchemeless() {
        let settings = AppSettings(defaults: makeDefaults())

        settings.serverURLString = ""
        #expect(settings.serverURL == nil)

        settings.serverURLString = "localhost:11434"
        #expect(settings.serverURL == nil)

        settings.serverURLString = "http://example.com:11434"
        #expect(settings.serverURL?.absoluteString == "http://example.com:11434")
    }

    @Test
    func persistsAndReloadsValues() {
        let defaults = makeDefaults()

        let settings = AppSettings(defaults: defaults)
        settings.serverURLString = "http://10.0.0.5:1134"
        settings.selectedModel = "mistral:7b"

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.serverURLString == "http://10.0.0.5:1134")
        #expect(reloaded.selectedModel == "mistral:7b")
    }
}
