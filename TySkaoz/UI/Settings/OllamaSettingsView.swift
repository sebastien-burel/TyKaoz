import SwiftUI

struct OllamaSettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var state: SettingsConnectionState = .idle
    @State private var models: [OllamaModel] = []

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Serveur") {
                TextField("URL", text: $settings.serverURLString, prompt: Text("http://host:port"))
                    .font(Brand.Fonts.mono(12))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await test() } }

                HStack {
                    Button("Tester la connexion") {
                        Task { await test() }
                    }
                    .disabled(state.isLoading)
                    SettingsConnectionStatus(state: state)
                }
            }

            Section("Modèle") {
                if models.isEmpty {
                    Text("Testez la connexion pour récupérer les modèles disponibles.")
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Modèle", selection: $settings.selectedModel) {
                        Text("Aucun").tag(String?.none)
                        ForEach(models) { model in
                            Text(model.name).tag(String?.some(model.name))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section {
                UseAsActiveButton(providerID: .ollama)
            }
        }
        .formStyle(.grouped)
    }

    private func test() async {
        guard let url = settings.serverURL else {
            state = .failure(message: "URL invalide.")
            return
        }
        state = .loading
        let client = OllamaClient(baseURL: url)
        do {
            let listed = try await client.listModels()
            models = listed
            state = .success(count: listed.count)
            if let current = settings.selectedModel, listed.contains(where: { $0.name == current }) {
                // keep
            } else {
                settings.selectedModel = listed.first?.name
            }
        } catch let error as OllamaClientError {
            state = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            state = .failure(message: error.localizedDescription)
        }
    }
}
