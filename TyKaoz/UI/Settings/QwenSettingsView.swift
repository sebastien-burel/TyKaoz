import SwiftUI

struct QwenSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        CloudProviderSettingsView(
            providerID: .qwen,
            keyPlaceholder: "Qwen Cloud (DashScope) API key",
            apiKey: $settings.qwenAPIKey,
            activeModel: $settings.qwenModel,
            allModelIDs: settings.qwenCatalog
        ) { key in
            let client = OpenAICompatibleClient(baseURL: QwenProvider.baseURL, apiKey: key)
            return try await client.listModels().map(\.id).sorted()
        }
    }
}
