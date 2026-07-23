import SwiftUI
import KaozKit

struct ZAISettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        CloudProviderSettingsView(
            providerID: .zai,
            keyPlaceholder: "z.ai (Zhipu GLM) API key",
            apiKey: $settings.zaiAPIKey,
            activeModel: $settings.zaiModel,
            allModelIDs: settings.zaiCatalog
        ) { key in
            let client = OpenAICompatibleClient(baseURL: ZAIProvider.baseURL, apiKey: key)
            return try await client.listModels().map(\.id).sorted()
        }
    }
}
