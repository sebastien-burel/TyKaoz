import SwiftUI

struct SettingsPanelView: View {
    @Environment(AppSettings.self) private var settings

    @State private var connectionState: ConnectionState = .idle
    @State private var availableModels: [OllamaModel] = []
    @State private var appleAvailability: ProviderAvailability?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Provider") {
                Picker("Provider", selection: $settings.selectedProviderID) {
                    Text("Ollama").tag("ollama")
                    Text("Apple Intelligence").tag("apple")
                }
                .pickerStyle(.segmented)
            }

            switch settings.selectedProviderID {
            case "apple":
                appleSection
            default:
                ollamaSection(settings: settings)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 360)
        .task(id: settings.selectedProviderID) {
            if settings.selectedProviderID == "apple" {
                appleAvailability = await AppleIntelligenceProvider().availability()
            }
        }
    }

    // MARK: - Ollama

    @ViewBuilder
    private func ollamaSection(settings: AppSettings) -> some View {
        @Bindable var settings = settings

        Section("Serveur Ollama") {
            TextField("URL", text: $settings.serverURLString, prompt: Text("http://host:port"))
                .font(Brand.Fonts.mono(12))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await testOllama() } }

            HStack {
                Button("Tester la connexion") {
                    Task { await testOllama() }
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

    private func testOllama() async {
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
            if let current = settings.selectedModel, models.contains(where: { $0.name == current }) {
                // keep
            } else {
                settings.selectedModel = models.first?.name
            }
        } catch let error as OllamaClientError {
            connectionState = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            connectionState = .failure(message: error.localizedDescription)
        }
    }

    // MARK: - Apple Intelligence

    @ViewBuilder
    private var appleSection: some View {
        Section("Apple Intelligence") {
            switch appleAvailability {
            case .ready:
                Label("Disponible", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(Brand.Fonts.body(13))
            case .unavailable(let reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(Brand.Fonts.body(12))
            case nil:
                ProgressView().controlSize(.small)
            }

            Text("Le modèle est exécuté localement par le système. Aucune configuration réseau requise.")
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
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
