import SwiftUI

/// Lets the user switch individual built-in tools on or off. Disabled tools
/// are never offered to the model.
struct ToolsSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                toolList
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Brand.Colors.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Outils")
                .font(Brand.Fonts.title(20))
                .foregroundStyle(Brand.Colors.ink)
            Text("""
            Choisissez les outils que le modèle peut utiliser. Les outils de \
            fichiers n'agissent que sur les dossiers autorisés.
            """)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(.secondary)
        }
    }

    private var toolList: some View {
        @Bindable var settings = settings
        return VStack(spacing: 0) {
            ForEach(ToolCatalog.allToolNames, id: \.self) { name in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ToolCatalog.label(for: name))
                                .font(Brand.Fonts.body(13))
                                .foregroundStyle(Brand.Colors.ink)
                            Text(name)
                                .font(Brand.Fonts.body(11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Toggle("", isOn: binding(for: name))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    if name == "web_search" {
                        braveKeyField(apiKey: $settings.braveAPIKey)
                    }
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
    }

    /// `web_search` needs a Brave subscription token; shown right under its
    /// row. The tool stays toggleable, but reports an error if used without a
    /// key.
    private func braveKeyField(apiKey: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SecureField("Clé API Brave", text: apiKey, prompt: Text("Jeton d'abonnement Brave Search"))
                .font(Brand.Fonts.mono(12))
                .textFieldStyle(.roundedBorder)
            Text("Stockée dans le trousseau macOS. Requise pour la recherche web.")
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { settings.isToolEnabled(name) },
            set: { settings.setToolEnabled($0, name: name) }
        )
    }
}
