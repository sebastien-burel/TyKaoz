import SwiftUI

struct GoogleSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        CloudProviderSettingsView(
            providerID: .google,
            keyPlaceholder: "Google AI Studio API key",
            apiKey: $settings.googleAPIKey,
            activeModel: $settings.googleModel,
            allModelIDs: settings.googleCatalog
        ) { key in
            let client = GoogleClient(apiKey: key)
            return try await client.listModels().map(\.id).sorted()
        }
    }
}
