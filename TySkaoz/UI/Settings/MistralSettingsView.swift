import SwiftUI

struct MistralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var state: SettingsConnectionState = .idle
    @State private var models: [MistralModelsResponse.Model] = []

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Authentification") {
                SecureField("Clé API", text: $settings.mistralAPIKey, prompt: Text("Mistral API key"))
                    .font(Brand.Fonts.mono(12))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await test() } }

                HStack {
                    Button("Tester la connexion") {
                        Task { await test() }
                    }
                    .disabled(state.isLoading || settings.mistralAPIKey.isEmpty)
                    SettingsConnectionStatus(state: state)
                }

                Text("La clé est stockée dans le trousseau macOS de cette app.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }

            Section("Modèle") {
                if models.isEmpty {
                    Text("Testez la connexion pour récupérer les modèles disponibles.")
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Modèle", selection: $settings.mistralModel) {
                        Text("Aucun").tag(String?.none)
                        ForEach(models) { model in
                            Text(model.id).tag(String?.some(model.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section {
                UseAsActiveButton(providerID: .mistral)
            }
        }
        .formStyle(.grouped)
    }

    private func test() async {
        guard !settings.mistralAPIKey.isEmpty else {
            state = .failure(message: "Clé manquante.")
            return
        }
        state = .loading
        let client = MistralClient(apiKey: settings.mistralAPIKey)
        do {
            let listed = try await client.listModels()
            models = listed
            state = .success(count: listed.count)
            if let current = settings.mistralModel, listed.contains(where: { $0.id == current }) {
                // keep
            } else {
                settings.mistralModel = listed.first?.id
            }
        } catch let error as MistralClientError {
            state = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            state = .failure(message: error.localizedDescription)
        }
    }
}
