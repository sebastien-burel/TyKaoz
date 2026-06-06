import SwiftUI

struct OpenAISettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        CloudProviderSettingsView(
            providerID: .openai,
            keyPlaceholder: "sk-...",
            apiKey: $settings.openaiAPIKey,
            activeModel: $settings.openaiModel,
            allModelIDs: settings.openaiCatalog
        ) { key in
            let client = OpenAICompatibleClient(baseURL: OpenAIProvider.baseURL, apiKey: key)
            return try await client.listModels().map(\.id).sorted()
        }
    }
}
