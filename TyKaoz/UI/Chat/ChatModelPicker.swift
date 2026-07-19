import SwiftUI
import TyKaozKitMLX
import TyKaozKit

/// Toolbar-sized menu that lets the user switch the active provider + model
/// in one gesture, listing only the models they've enabled per provider.
struct ChatModelPicker: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ModelCatalogService.self) private var catalog
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            ForEach(ProviderID.allCases) { provider in
                providerSection(provider)
            }

            Divider()

            Button {
                openWindow(id: TyKaozApp.settingsWindowID)
            } label: {
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
        case .comfyui:
            return formatLabel(provider, model: settings.comfyuiModel)
        case .deepseek:
            return formatLabel(provider, model: settings.deepseekModel)
        case .google:
            return formatLabel(provider, model: settings.googleModel)
        case .localOpenAI:
            return formatLabel(provider, model: settings.localOpenAIModel)
        case .mlx:
            return formatLabel(
                provider,
                model: settings.mlxChatModelID
                    .flatMap { catalog.entry(forID: $0)?.name ?? $0 }
            )
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
        case .mlx:
            // Catalog is static and installation = "available".
            // Only show models actually on disk so the picker doesn't
            // dangle entries that would 404 on chat(). Curated models
            // first, then hand-added custom slugs (labelled by slug).
            let installed = mlxInstalledEntries
            if !installed.isEmpty {
                Section(provider.displayName) {
                    ForEach(installed) { entry in
                        Button {
                            activate(provider: .mlx, model: entry.id)
                        } label: {
                            if isActive(provider: .mlx, model: entry.id) {
                                Label(entry.name, systemImage: "checkmark")
                            } else {
                                Text(entry.name)
                            }
                        }
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

    private struct MLXEntry: Identifiable {
        let id: String
        let name: String
    }

    /// Installed MLX chat models offered in the picker: curated
    /// catalog entries first (shown by display name), then hand-added
    /// custom slugs that aren't in the catalog (shown by slug).
    private var mlxInstalledEntries: [MLXEntry] {
        let curated = Set(catalog.chats.map(\.id))
        let catalogEntries = catalog.chats
            .filter { MLXModelStore.shared.isInstalled(modelID: $0.id) }
            .map { MLXEntry(id: $0.id, name: $0.name) }
        let customEntries = settings.mlxCustomChatModelIDs
            .filter { !curated.contains($0) && MLXModelStore.shared.isInstalled(modelID: $0) }
            .map { MLXEntry(id: $0, name: $0) }
        return catalogEntries + customEntries
    }

    private func isActive(provider: ProviderID, model: String?) -> Bool {
        guard settings.selectedProviderID == provider.rawValue else { return false }
        switch provider {
        case .anthropic: return settings.anthropicModel == model
        case .apple:     return true
        case .comfyui:   return settings.comfyuiModel == model
        case .deepseek:  return settings.deepseekModel == model
        case .google:    return settings.googleModel == model
        case .localOpenAI: return settings.localOpenAIModel == model
        case .mlx:       return settings.mlxChatModelID == model
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
        case .comfyui:   settings.comfyuiModel = model
        case .deepseek:  settings.deepseekModel = model
        case .google:    settings.googleModel = model
        case .localOpenAI: settings.localOpenAIModel = model
        case .mlx:       settings.mlxChatModelID = model
        case .mistral:   settings.mistralModel = model
        case .ollama:    settings.selectedModel = model
        case .openai:    settings.openaiModel = model
        case .qwen:      settings.qwenModel = model
        case .zai:       settings.zaiModel = model
        }
    }
}
