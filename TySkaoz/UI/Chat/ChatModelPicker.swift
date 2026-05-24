import SwiftUI

/// Toolbar-sized menu that lets the user switch the active provider + model
/// in one gesture, listing only the models they've enabled per provider.
struct ChatModelPicker: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Menu {
            ForEach(ProviderID.allCases) { provider in
                providerSection(provider)
            }

            Divider()

            SettingsLink {
                Label("Gérer les modèles…", systemImage: "gearshape")
            }
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
    }

    // MARK: - Label shown in the toolbar

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .foregroundStyle(Brand.Colors.tide)
            Text(activeLabel)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(Brand.Colors.ink)
                .lineLimit(1)
        }
    }

    private var activeLabel: String {
        switch settings.selectedProviderID {
        case "apple":
            return AppleIntelligenceProvider().displayName
        case "ollama":
            if let model = settings.selectedModel, !model.isEmpty {
                return "Ollama · \(model)"
            }
            return "Ollama (aucun modèle)"
        case "mistral":
            if let model = settings.mistralModel, !model.isEmpty {
                return "Mistral · \(model)"
            }
            return "Mistral (aucun modèle)"
        default:
            return "Aucun modèle"
        }
    }

    // MARK: - Per-provider menu sections

    @ViewBuilder
    private func providerSection(_ provider: ProviderID) -> some View {
        switch provider {
        case .apple:
            Section(provider.displayName) {
                Button {
                    activate(provider: .apple, model: nil)
                } label: {
                    if isActive(provider: .apple, model: nil) {
                        Label("Modèle système", systemImage: "checkmark")
                    } else {
                        Text("Modèle système")
                    }
                }
            }
        default:
            let enabled = settings.enabledModels(for: provider).sorted()
            if !enabled.isEmpty {
                Section(provider.displayName) {
                    ForEach(enabled, id: \.self) { model in
                        Button {
                            activate(provider: provider, model: model)
                        } label: {
                            if isActive(provider: provider, model: model) {
                                Label(model, systemImage: "checkmark")
                            } else {
                                Text(model)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func isActive(provider: ProviderID, model: String?) -> Bool {
        guard settings.selectedProviderID == provider.rawValue else { return false }
        switch provider {
        case .apple:   return true
        case .ollama:  return settings.selectedModel == model
        case .mistral: return settings.mistralModel == model
        }
    }

    private func activate(provider: ProviderID, model: String?) {
        settings.selectedProviderID = provider.rawValue
        switch provider {
        case .ollama:  settings.selectedModel = model
        case .mistral: settings.mistralModel = model
        case .apple:   break
        }
    }
}
