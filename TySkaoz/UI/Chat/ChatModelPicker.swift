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
        guard let provider = ProviderID(settings.selectedProviderID) else {
            return "Aucun modèle"
        }
        switch provider {
        case .anthropic:
            return formatLabel(provider, model: settings.anthropicModel)
        case .apple:
            return provider.displayName
        case .deepseek:
            return formatLabel(provider, model: settings.deepseekModel)
        case .google:
            return formatLabel(provider, model: settings.googleModel)
        case .localOpenAI:
            return formatLabel(provider, model: settings.localOpenAIModel)
        case .mlx:
            // Chat side of MLX lands in Phase C — picker reads
            // "aucun modèle" until then.
            return formatLabel(provider, model: String?.none)
        case .mistral:
            return formatLabel(provider, model: settings.mistralModel)
        case .ollama:
            return formatLabel(provider, model: settings.selectedModel)
        case .openai:
            return formatLabel(provider, model: settings.openaiModel)
        case .qwen:
            return formatLabel(provider, model: settings.qwenModel)
        case .zai:
            return formatLabel(provider, model: settings.zaiModel)
        }
    }

    private func formatLabel(_ provider: ProviderID, model: String?) -> String {
        if let model, !model.isEmpty {
            return "\(provider.displayName) · \(model)"
        }
        return "\(provider.displayName) (aucun modèle)"
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
        case .anthropic: return settings.anthropicModel == model
        case .apple:     return true
        case .deepseek:  return settings.deepseekModel == model
        case .google:    return settings.googleModel == model
        case .localOpenAI: return settings.localOpenAIModel == model
        case .mlx:       return false
        case .mistral:   return settings.mistralModel == model
        case .ollama:    return settings.selectedModel == model
        case .openai:    return settings.openaiModel == model
        case .qwen:      return settings.qwenModel == model
        case .zai:       return settings.zaiModel == model
        }
    }

    private func activate(provider: ProviderID, model: String?) {
        settings.selectedProviderID = provider.rawValue
        switch provider {
        case .anthropic: settings.anthropicModel = model
        case .apple:     break
        case .deepseek:  settings.deepseekModel = model
        case .google:    settings.googleModel = model
        case .localOpenAI: settings.localOpenAIModel = model
        case .mlx:       break
        case .mistral:   settings.mistralModel = model
        case .ollama:    settings.selectedModel = model
        case .openai:    settings.openaiModel = model
        case .qwen:      settings.qwenModel = model
        case .zai:       settings.zaiModel = model
        }
    }
}
