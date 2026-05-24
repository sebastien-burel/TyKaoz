import SwiftUI

struct AnthropicSettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var state: SettingsConnectionState = .idle

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Authentification") {
                SecureField("Clé API", text: $settings.anthropicAPIKey, prompt: Text("sk-ant-..."))
                    .font(Brand.Fonts.mono(12))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await test() } }

                HStack {
                    Button("Tester la connexion") {
                        Task { await test() }
                    }
                    .disabled(state.isLoading || settings.anthropicAPIKey.isEmpty)
                    SettingsConnectionStatus(state: state)
                }

                Text("La clé est stockée dans le trousseau macOS de cette app.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }

            ModelCurationSummary(
                provider: .anthropic,
                allModelIDs: settings.anthropicCatalog,
                activeModel: $settings.anthropicModel
            )

            Section {
                UseAsActiveButton(providerID: .anthropic)
            }
        }
        .formStyle(.grouped)
    }

    private func test() async {
        guard !settings.anthropicAPIKey.isEmpty else {
            state = .failure(message: "Clé manquante.")
            return
        }
        state = .loading
        let client = AnthropicClient(apiKey: settings.anthropicAPIKey)
        do {
            let listed = try await client.listModels()
            settings.setCatalog(listed.map(\.id).sorted(), for: .anthropic)
            state = .success(count: listed.count)
        } catch let error as AnthropicClientError {
            state = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            state = .failure(message: error.localizedDescription)
        }
    }
}
