import SwiftUI
import KaozKit

struct AppleSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PluginStore.self) private var plugins

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

            Section("Outils") {
                Text("""
                Le modèle on-device a une fenêtre de contexte très courte. \
                Aucun outil n'est actif par défaut — activez seulement ceux \
                dont vous avez vraiment besoin (idéalement 1 ou 2).
                """)
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)

                ForEach(ToolCatalog.allToolNames, id: \.self) { name in
                    toolRow(name: name, label: ToolCatalog.label(for: name))
                }
                ForEach(pluginToolNames, id: \.self) { name in
                    toolRow(name: name, label: name)
                }
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

    private var pluginToolNames: [String] {
        plugins.tools().map(\.spec.name).sorted()
    }

    private func toolRow(name: String, label: String) -> some View {
        Toggle(isOn: binding(for: name)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Brand.Fonts.body(13))
                Text(name)
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { settings.isAppleToolEnabled(name) },
            set: { settings.setAppleToolEnabled($0, name: name) }
        )
    }
}
