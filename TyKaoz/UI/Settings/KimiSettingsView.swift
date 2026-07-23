import SwiftUI
import KaozKit

/// Kimi K3 (Moonshot AI). OpenAI-compatible, so the model list comes from the
/// standard `/v1/models` endpoint and the provider runs as JS (JSProviders.kimi).
struct KimiSettingsView: View {
    @Environment(AppSettings.self) private var settings

    private static let baseURL = URL(string: "https://api.moonshot.ai/v1")!

    var body: some View {
        @Bindable var settings = settings

        CloudProviderSettingsView(
            providerID: .kimi,
            keyPlaceholder: "Moonshot (Kimi) API key",
            apiKey: $settings.kimiAPIKey,
            activeModel: $settings.kimiModel,
            allModelIDs: settings.kimiCatalog
        ) { key in
            let client = OpenAICompatibleClient(baseURL: Self.baseURL, apiKey: key)
            return try await client.listModels().map(\.id).sorted()
        }
    }
}
