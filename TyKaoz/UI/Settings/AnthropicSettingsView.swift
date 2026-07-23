import SwiftUI
import KaozKit

struct AnthropicSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        CloudProviderSettingsView(
            providerID: .anthropic,
            keyPlaceholder: "sk-ant-...",
            apiKey: $settings.anthropicAPIKey,
            activeModel: $settings.anthropicModel,
            allModelIDs: settings.anthropicCatalog
        ) { key in
            let client = AnthropicClient(apiKey: key)
            return try await client.listModels().map(\.id).sorted()
        }
    }
}
