import SwiftUI
import TyKaozKit

struct DeepSeekSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        CloudProviderSettingsView(
            providerID: .deepseek,
            keyPlaceholder: "DeepSeek API key",
            apiKey: $settings.deepseekAPIKey,
            activeModel: $settings.deepseekModel,
            allModelIDs: settings.deepseekCatalog
        ) { key in
            let client = OpenAICompatibleClient(baseURL: DeepSeekProvider.baseURL, apiKey: key)
            return try await client.listModels().map(\.id).sorted()
        }
    }
}
