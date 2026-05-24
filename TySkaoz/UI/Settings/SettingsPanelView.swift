import SwiftUI

struct SettingsPanelView: View {
    @Environment(AppSettings.self) private var settings

    @State private var ollamaConnection: ConnectionState = .idle
    @State private var ollamaModels: [OllamaModel] = []

    @State private var mistralConnection: ConnectionState = .idle
    @State private var mistralModels: [MistralModelsResponse.Model] = []

    @State private var appleAvailability: ProviderAvailability?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Provider") {
                Picker("Provider", selection: $settings.selectedProviderID) {
                    Text("Ollama").tag("ollama")
                    Text("Mistral").tag("mistral")
                    Text("Apple Intelligence").tag("apple")
                }
                .pickerStyle(.segmented)
            }

            switch settings.selectedProviderID {
            case "apple":   appleSection
            case "mistral": mistralSection(settings: settings)
            default:        ollamaSection(settings: settings)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 380)
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
                .disabled(ollamaConnection.isLoading)
                connectionStatusView(ollamaConnection)
            }
        }

        Section("Modèle") {
            if ollamaModels.isEmpty {
                Text("Testez la connexion pour récupérer les modèles disponibles.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            } else {
                Picker("Modèle", selection: $settings.selectedModel) {
                    Text("Aucun").tag(String?.none)
                    ForEach(ollamaModels) { model in
                        Text(model.name).tag(String?.some(model.name))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func testOllama() async {
        guard let url = settings.serverURL else {
            ollamaConnection = .failure(message: "URL invalide.")
            return
        }
        ollamaConnection = .loading
        let client = OllamaClient(baseURL: url)
        do {
            let models = try await client.listModels()
            ollamaModels = models
            ollamaConnection = .success(count: models.count)
            if let current = settings.selectedModel, models.contains(where: { $0.name == current }) {
                // keep
            } else {
                settings.selectedModel = models.first?.name
            }
        } catch let error as OllamaClientError {
            ollamaConnection = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            ollamaConnection = .failure(message: error.localizedDescription)
        }
    }

    // MARK: - Mistral

    @ViewBuilder
    private func mistralSection(settings: AppSettings) -> some View {
        @Bindable var settings = settings

        Section("Mistral") {
            SecureField("Clé API", text: $settings.mistralAPIKey, prompt: Text("Mistral API key"))
                .font(Brand.Fonts.mono(12))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await testMistral() } }

            HStack {
                Button("Tester la connexion") {
                    Task { await testMistral() }
                }
                .disabled(mistralConnection.isLoading || settings.mistralAPIKey.isEmpty)
                connectionStatusView(mistralConnection)
            }

            Text("La clé est stockée dans le trousseau macOS de cette app.")
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
        }

        Section("Modèle") {
            if mistralModels.isEmpty {
                Text("Testez la connexion pour récupérer les modèles disponibles.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            } else {
                Picker("Modèle", selection: $settings.mistralModel) {
                    Text("Aucun").tag(String?.none)
                    ForEach(mistralModels) { model in
                        Text(model.id).tag(String?.some(model.id))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func testMistral() async {
        guard !settings.mistralAPIKey.isEmpty else {
            mistralConnection = .failure(message: "Clé manquante.")
            return
        }
        mistralConnection = .loading
        let client = MistralClient(apiKey: settings.mistralAPIKey)
        do {
            let models = try await client.listModels()
            mistralModels = models
            mistralConnection = .success(count: models.count)
            if let current = settings.mistralModel, models.contains(where: { $0.id == current }) {
                // keep
            } else {
                settings.mistralModel = models.first?.id
            }
        } catch let error as MistralClientError {
            mistralConnection = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            mistralConnection = .failure(message: error.localizedDescription)
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

    // MARK: - Shared status row

    @ViewBuilder
    private func connectionStatusView(_ state: ConnectionState) -> some View {
        switch state {
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
}

private enum ConnectionState {
    case idle
    case loading
    case success(count: Int)
    case failure(message: String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
