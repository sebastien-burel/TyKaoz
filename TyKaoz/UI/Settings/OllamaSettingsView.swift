import SwiftUI
import KaozKit

struct OllamaSettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var state: SettingsConnectionState = .idle

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

            ModelCurationSummary(
                provider: .ollama,
                allModelIDs: settings.ollamaCatalog,
                activeModel: $settings.selectedModel
            )

            Section {
                UseAsActiveButton(providerID: .ollama)
            }

            Section("Implémentation") {
                Toggle("Utiliser l'implémentation JavaScript",
                       isOn: $settings.useJSProviders)
                Text("Le provider tourne dans le moteur XS (XMLHttpRequest natif) "
                     + "au lieu du code Swift. Comportement identique côté chat.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
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
            settings.setCatalog(listed.map { $0.name }, for: .ollama)
            state = .success(count: listed.count)
        } catch let error as OllamaClientError {
            state = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            state = .failure(message: error.localizedDescription)
        }
    }
}
