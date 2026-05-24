import SwiftUI

struct SettingsPanelView: View {
    @Environment(AppSettings.self) private var settings

    @State private var connectionState: ConnectionState = .idle
    @State private var availableModels: [OllamaModel] = []

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Serveur Ollama") {
                TextField("URL", text: $settings.serverURLString, prompt: Text("http://host:port"))
                    .font(Brand.Fonts.mono(12))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await testConnection() } }

                HStack {
                    Button("Tester la connexion") {
                        Task { await testConnection() }
                    }
                    .disabled(connectionState.isLoading)

                    connectionStatusView
                }
            }

            Section("Modèle") {
                if availableModels.isEmpty {
                    Text("Testez la connexion pour récupérer les modèles disponibles.")
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Modèle", selection: $settings.selectedModel) {
                        Text("Aucun").tag(String?.none)
                        ForEach(availableModels) { model in
                            Text(model.name).tag(String?.some(model.name))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionState {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView().controlSize(.small)
        case .success(let count):
            Label("\(count) modèles", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(Brand.Fonts.body(12))
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(Brand.Fonts.body(12))
                .lineLimit(2)
        }
    }

    private func testConnection() async {
        guard let url = settings.serverURL else {
            connectionState = .failure(message: "URL invalide.")
            return
        }
        connectionState = .loading
        let client = OllamaClient(baseURL: url)
        do {
            let models = try await client.listModels()
            availableModels = models
            connectionState = .success(modelCount: models.count)
            // Garder la sélection si elle est toujours valide ; sinon, choisir le premier.
            if let current = settings.selectedModel, models.contains(where: { $0.name == current }) {
                // OK
            } else {
                settings.selectedModel = models.first?.name
            }
        } catch let error as OllamaClientError {
            connectionState = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            connectionState = .failure(message: error.localizedDescription)
        }
    }
}

private enum ConnectionState {
    case idle
    case loading
    case success(modelCount: Int)
    case failure(message: String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
