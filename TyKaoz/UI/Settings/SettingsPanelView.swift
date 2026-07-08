import SwiftUI

/// Top-level Settings window. Sidebar lists providers; the detail pane shows
/// the selected provider's configuration. Scales to N providers without
/// reshaping the layout.
struct SettingsPanelView: View {
    @Environment(AppSettings.self) private var settings

    @State private var selection: SettingsSection = .provider(.ollama)

    var body: some View {
        NavigationSplitView {
            ProvidersSidebar(selection: $selection)
                .frame(minWidth: 180)
        } detail: {
            detail
                .frame(minWidth: 480, minHeight: 380)
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 720, minHeight: 440)
        .onAppear {
            // Open on the currently-active provider, if it matches.
            if let active = ProviderID(settings.selectedProviderID) {
                selection = .provider(active)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .provider(.anthropic): AnthropicSettingsView()
        case .provider(.apple):     AppleSettingsView()
        case .provider(.comfyui):   ComfyUISettingsView()
        case .provider(.deepseek):  DeepSeekSettingsView()
        case .provider(.google):    GoogleSettingsView()
        case .provider(.localOpenAI): LocalOpenAISettingsView()
        case .provider(.mistral):   MistralSettingsView()
        case .provider(.mlx):       MLXSettingsView()
        case .provider(.ollama):    OllamaSettingsView()
        case .provider(.openai):    OpenAISettingsView()
        case .provider(.qwen):      QwenSettingsView()
        case .provider(.zai):       ZAISettingsView()
        case .tools:                ToolsSettingsView()
        case .fileSpaces:           FileSpacesSettingsView()
        case .memory:               MemorySettingsView()
        case .plugins:              PluginsSettingsView()
        case .wiki:                 WikiSettingsView()
        }
    }
}

/// A selectable settings section: one per provider, plus the shared tools
/// panes (tool toggles, file spaces, memory, plugins).
enum SettingsSection: Hashable {
    case provider(ProviderID)
    case tools
    case fileSpaces
    case memory
    case plugins
    case wiki

    var title: String {
        switch self {
        case .provider(let id): return id.displayName
        case .tools:            return "Outils"
        case .fileSpaces:       return "Dossiers autorisés"
        case .memory:           return "Préférences"
        case .plugins:          return "Plugins"
        case .wiki:             return "Wiki"
        }
    }
}

// MARK: - Sidebar

private struct ProvidersSidebar: View {
    @Environment(AppSettings.self) private var settings
    @Binding var selection: SettingsSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("Providers")

                ForEach(ProviderID.allCases) { id in
                    providerRow(for: id)
                }

                sectionLabel("Outils")
                toolRow(title: "Outils", systemImage: "wrench.and.screwdriver", section: .tools)
                toolRow(title: "Dossiers", systemImage: "folder", section: .fileSpaces)
                toolRow(title: "Préférences", systemImage: "brain", section: .memory)
                toolRow(title: "Plugins", systemImage: "puzzlepiece.extension", section: .plugins)
                toolRow(title: "Wiki", systemImage: "books.vertical", section: .wiki)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Brand.Colors.paper)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Brand.Fonts.body(11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func providerRow(for id: ProviderID) -> some View {
        let isSelected = selection == .provider(id)
        return HStack(spacing: 8) {
            Circle()
                .fill(dotColor(for: id))
                .frame(width: 8, height: 8)
            Text(id.displayName)
                .font(Brand.Fonts.body(13))
                .foregroundStyle(Brand.Colors.ink)
            Spacer()
            if settings.selectedProviderID == id.rawValue {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.Colors.tide)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Brand.Colors.slate.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .onTapGesture { selection = .provider(id) }
    }

    private func toolRow(title: String, systemImage: String, section: SettingsSection) -> some View {
        let isSelected = selection == section
        return HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(Brand.Colors.tide)
                .frame(width: 8)
            Text(title)
                .font(Brand.Fonts.body(13))
                .foregroundStyle(Brand.Colors.ink)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Brand.Colors.slate.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .onTapGesture { selection = section }
    }

    /// Quick heuristic: green if a working configuration is on file, gray if
    /// missing essentials, orange otherwise. (Doesn't probe the network — it's
    /// just based on local state to stay snappy.)
    private func dotColor(for id: ProviderID) -> Color {
        switch id {
        case .anthropic:
            return (!settings.anthropicAPIKey.isEmpty && settings.anthropicModel?.isEmpty == false)
                ? .green : .gray
        case .apple:
            return AppleIntelligenceProvider.isReady ? .green : .gray
        case .comfyui:
            return (settings.comfyuiBaseURL != nil && !settings.comfyuiWorkflows.isEmpty)
                ? .green : .gray
        case .deepseek:
            return (!settings.deepseekAPIKey.isEmpty && settings.deepseekModel?.isEmpty == false)
                ? .green : .gray
        case .google:
            return (!settings.googleAPIKey.isEmpty && settings.googleModel?.isEmpty == false)
                ? .green : .gray
        case .localOpenAI:
            return (settings.localOpenAIBaseURL != nil && settings.localOpenAIModel?.isEmpty == false)
                ? .green : .gray
        case .mlx:
            // Green once a chat model is on disk — no API key to check,
            // availability is "a usable model is downloaded" — counting
            // hand-added custom slugs, not just the curated catalog.
            let hasCurated = ModelCatalogService.shared.chats.contains {
                MLXModelStore.shared.isInstalled(modelID: $0.id)
            }
            let hasCustom = settings.mlxCustomChatModelIDs.contains {
                MLXModelStore.shared.isInstalled(modelID: $0)
            }
            return (hasCurated || hasCustom) ? .green : .gray
        case .mistral:
            return (!settings.mistralAPIKey.isEmpty && settings.mistralModel?.isEmpty == false)
                ? .green : .gray
        case .ollama:
            return (settings.serverURL != nil && settings.selectedModel?.isEmpty == false)
                ? .green : .gray
        case .openai:
            return (!settings.openaiAPIKey.isEmpty && settings.openaiModel?.isEmpty == false)
                ? .green : .gray
        case .qwen:
            return (!settings.qwenAPIKey.isEmpty && settings.qwenModel?.isEmpty == false)
                ? .green : .gray
        case .zai:
            return (!settings.zaiAPIKey.isEmpty && settings.zaiModel?.isEmpty == false)
                ? .green : .gray
        }
    }
}

// MARK: - Provider identity

enum ProviderID: String, CaseIterable, Identifiable, Hashable {
    case anthropic
    case apple
    case comfyui
    case deepseek
    case google
    case localOpenAI
    case mistral
    case mlx
    case ollama
    case openai
    case qwen
    case zai

    var id: String { rawValue }

    init?(_ raw: String) {
        switch raw {
        case "anthropic":   self = .anthropic
        case "apple":       self = .apple
        case "comfyui":     self = .comfyui
        case "deepseek":    self = .deepseek
        case "google":      self = .google
        case "localOpenAI": self = .localOpenAI
        case "mistral":     self = .mistral
        case "mlx":         self = .mlx
        case "ollama":      self = .ollama
        case "openai":      self = .openai
        case "qwen":        self = .qwen
        case "zai":         self = .zai
        default:            return nil
        }
    }

    var displayName: String {
        switch self {
        case .anthropic:    return "Anthropic"
        case .apple:        return "Apple Intelligence"
        case .comfyui:      return "ComfyUI"
        case .deepseek:     return "DeepSeek"
        case .google:       return "Google Gemini"
        case .localOpenAI:  return "Compatible OpenAI"
        case .mistral:      return "Mistral"
        case .mlx:          return "Sur ce Mac"
        case .ollama:       return "Ollama"
        case .openai:       return "OpenAI"
        case .qwen:         return "Qwen Cloud"
        case .zai:          return "z.ai"
        }
    }
}

// MARK: - Active-provider button shared across panels

struct UseAsActiveButton: View {
    @Environment(AppSettings.self) private var settings
    let providerID: ProviderID

    var body: some View {
        if settings.selectedProviderID == providerID.rawValue {
            Label("Provider actif", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(Brand.Fonts.body(12))
        } else {
            Button("Définir comme provider actif") {
                settings.selectedProviderID = providerID.rawValue
            }
        }
    }
}

// MARK: - Connection status row used by multiple panels

enum SettingsConnectionState {
    case idle
    case loading
    case success(count: Int)
    case failure(message: String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct SettingsConnectionStatus: View {
    let state: SettingsConnectionState

    var body: some View {
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
