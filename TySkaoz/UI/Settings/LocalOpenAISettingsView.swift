import SwiftUI

/// Settings for the generic OpenAI-compatible local provider. Covers
/// vLLM (`/v1/...`), LM Studio, llama.cpp's `server`, anything that
/// speaks the OpenAI API at a user-provided host. URL + optional API
/// key, then list-models hits `/v1/models` to populate the picker.
struct LocalOpenAISettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var state: SettingsConnectionState = .idle

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Serveur") {
                TextField(
                    "URL",
                    text: $settings.localOpenAIBaseURLString,
                    prompt: Text("http://localhost:8000")
                )
                .font(Brand.Fonts.mono(12))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await test() } }

                Text("""
                vLLM, LM Studio, llama.cpp server… Tout serveur qui \
                expose l'API OpenAI à une URL self-host. Sans le \
                suffixe `/v1`.
                """)
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
            }

            Section("Clé API (optionnelle)") {
                SecureField(
                    "Bearer token",
                    text: $settings.localOpenAIAPIKey,
                    prompt: Text("Laisser vide pour un serveur sans auth")
                )
                .font(Brand.Fonts.mono(12))
                .textFieldStyle(.roundedBorder)

                Text("Stockée dans le trousseau macOS.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Tester la connexion") {
                        Task { await test() }
                    }
                    .disabled(state.isLoading || settings.localOpenAIBaseURL == nil)
                    SettingsConnectionStatus(state: state)
                }
            }

            ModelCurationSummary(
                provider: .localOpenAI,
                allModelIDs: settings.localOpenAICatalog,
                activeModel: $settings.localOpenAIModel
            )

            Section {
                UseAsActiveButton(providerID: .localOpenAI)
            }
        }
        .formStyle(.grouped)
    }

    private func test() async {
        guard let url = settings.localOpenAIBaseURL else {
            state = .failure(message: "URL invalide.")
            return
        }
        state = .loading
        let client = OpenAICompatibleClient(
            baseURL: url,
            apiKey: settings.localOpenAIAPIKey
        )
        do {
            let listed = try await client.listModels()
            settings.setCatalog(listed.map(\.id), for: .localOpenAI)
            state = .success(count: listed.count)
        } catch let error as OpenAICompatibleError {
            state = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            state = .failure(message: error.localizedDescription)
        }
    }
}
