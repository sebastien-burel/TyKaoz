import SwiftUI
import TyKaozKit

/// Shared layout for any cloud-style provider settings panel (API key in
/// Keychain + connection test + model curation + active-provider button).
/// Each provider's settings view collapses to a few lines on top of this
/// component.
struct CloudProviderSettingsView: View {
    @Environment(AppSettings.self) private var settings

    let providerID: ProviderID
    let keyPlaceholder: String
    @Binding var apiKey: String
    @Binding var activeModel: String?
    let allModelIDs: [String]
    /// Performs the connection test against the provider and returns the raw
    /// list of model IDs. The component writes them to settings.catalog.
    let testConnection: (_ apiKey: String) async throws -> [String]

    @State private var state: SettingsConnectionState = .idle

    var body: some View {
        Form {
            Section("Authentification") {
                SecureField("Clé API", text: $apiKey, prompt: Text(keyPlaceholder))
                    .font(Brand.Fonts.mono(12))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await test() } }

                HStack {
                    Button("Tester la connexion") {
                        Task { await test() }
                    }
                    .disabled(state.isLoading || apiKey.isEmpty)
                    SettingsConnectionStatus(state: state)
                }

                Text("La clé est stockée dans le trousseau macOS de cette app.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }

            ModelCurationSummary(
                provider: providerID,
                allModelIDs: allModelIDs,
                activeModel: $activeModel
            )

            Section {
                UseAsActiveButton(providerID: providerID)
            }
        }
        .formStyle(.grouped)
    }

    private func test() async {
        guard !apiKey.isEmpty else {
            state = .failure(message: "Clé manquante.")
            return
        }
        state = .loading
        do {
            let ids = try await testConnection(apiKey)
            settings.setCatalog(ids, for: providerID)
            state = .success(count: ids.count)
        } catch let error as LocalizedError {
            state = .failure(message: error.errorDescription ?? "Erreur.")
        } catch {
            state = .failure(message: error.localizedDescription)
        }
    }
}
