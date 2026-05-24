import SwiftUI

struct DeepSeekSettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var state: SettingsConnectionState = .idle

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Authentification") {
                SecureField("Clé API", text: $settings.deepseekAPIKey, prompt: Text("DeepSeek API key"))
                    .font(Brand.Fonts.mono(12))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await test() } }

                HStack {
                    Button("Tester la connexion") {
                        Task { await test() }
                    }
                    .disabled(state.isLoading || settings.deepseekAPIKey.isEmpty)
                    SettingsConnectionStatus(state: state)
                }

                Text("La clé est stockée dans le trousseau macOS de cette app.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }

            ModelCurationSummary(
                provider: .deepseek,
                allModelIDs: settings.deepseekCatalog,
                activeModel: $settings.deepseekModel
            )

            Section {
                UseAsActiveButton(providerID: .deepseek)
            }
        }
        .formStyle(.grouped)
    }

    private func test() async {
        guard !settings.deepseekAPIKey.isEmpty else {
            state = .failure(message: "Clé manquante.")
            return
        }
        state = .loading
        let client = OpenAICompatibleClient(baseURL: DeepSeekProvider.baseURL, apiKey: settings.deepseekAPIKey)
        do {
            let listed = try await client.listModels()
            settings.setCatalog(listed.map(\.id).sorted(), for: .deepseek)
            state = .success(count: listed.count)
        } catch let error as OpenAICompatibleError {
            state = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            state = .failure(message: error.localizedDescription)
        }
    }
}
