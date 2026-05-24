import SwiftUI

struct GoogleSettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var state: SettingsConnectionState = .idle

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Authentification") {
                SecureField("Clé API", text: $settings.googleAPIKey, prompt: Text("Google AI Studio API key"))
                    .font(Brand.Fonts.mono(12))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await test() } }

                HStack {
                    Button("Tester la connexion") {
                        Task { await test() }
                    }
                    .disabled(state.isLoading || settings.googleAPIKey.isEmpty)
                    SettingsConnectionStatus(state: state)
                }

                Text("La clé est stockée dans le trousseau macOS de cette app.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }

            ModelCurationSummary(
                provider: .google,
                allModelIDs: settings.googleCatalog,
                activeModel: $settings.googleModel
            )

            Section {
                UseAsActiveButton(providerID: .google)
            }
        }
        .formStyle(.grouped)
    }

    private func test() async {
        guard !settings.googleAPIKey.isEmpty else {
            state = .failure(message: "Clé manquante.")
            return
        }
        state = .loading
        let client = GoogleClient(apiKey: settings.googleAPIKey)
        do {
            let listed = try await client.listModels()
            settings.setCatalog(listed.map(\.id).sorted(), for: .google)
            state = .success(count: listed.count)
        } catch let error as GoogleClientError {
            state = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            state = .failure(message: error.localizedDescription)
        }
    }
}
