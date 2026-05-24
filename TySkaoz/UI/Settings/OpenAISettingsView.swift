import SwiftUI

struct OpenAISettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var state: SettingsConnectionState = .idle

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Authentification") {
                SecureField("Clé API", text: $settings.openaiAPIKey, prompt: Text("sk-..."))
                    .font(Brand.Fonts.mono(12))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await test() } }

                HStack {
                    Button("Tester la connexion") {
                        Task { await test() }
                    }
                    .disabled(state.isLoading || settings.openaiAPIKey.isEmpty)
                    SettingsConnectionStatus(state: state)
                }

                Text("La clé est stockée dans le trousseau macOS de cette app.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }

            ModelCurationSummary(
                provider: .openai,
                allModelIDs: settings.openaiCatalog,
                activeModel: $settings.openaiModel
            )

            Section {
                UseAsActiveButton(providerID: .openai)
            }
        }
        .formStyle(.grouped)
    }

    private func test() async {
        guard !settings.openaiAPIKey.isEmpty else {
            state = .failure(message: "Clé manquante.")
            return
        }
        state = .loading
        let client = OpenAICompatibleClient(baseURL: OpenAIProvider.baseURL, apiKey: settings.openaiAPIKey)
        do {
            let listed = try await client.listModels()
            settings.setCatalog(listed.map(\.id).sorted(), for: .openai)
            state = .success(count: listed.count)
        } catch let error as OpenAICompatibleError {
            state = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            state = .failure(message: error.localizedDescription)
        }
    }
}
