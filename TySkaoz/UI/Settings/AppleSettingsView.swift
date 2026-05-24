import SwiftUI

struct AppleSettingsView: View {
    @State private var availability: ProviderAvailability?

    var body: some View {
        Form {
            Section("État") {
                switch availability {
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

            Section {
                UseAsActiveButton(providerID: .apple)
            }
        }
        .formStyle(.grouped)
        .task {
            availability = await AppleIntelligenceProvider().availability()
        }
    }
}
