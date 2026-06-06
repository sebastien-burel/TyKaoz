import SwiftUI

struct MistralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        CloudProviderSettingsView(
            providerID: .mistral,
            keyPlaceholder: "Mistral API key",
            apiKey: $settings.mistralAPIKey,
            activeModel: $settings.mistralModel,
            allModelIDs: settings.mistralCatalog
        ) { key in
            let client = OpenAICompatibleClient(baseURL: MistralProvider.baseURL, apiKey: key)
            return try await client.listModels().map(\.id).sorted()
        }
    }
}
