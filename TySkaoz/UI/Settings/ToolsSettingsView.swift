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
        VStack(spacing: 0) {
            ForEach(ToolCatalog.allSpecs, id: \.name) { spec in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ToolCatalog.label(for: spec.name))
                            .font(Brand.Fonts.body(13))
                            .foregroundStyle(Brand.Colors.ink)
                        Text(spec.name)
                            .font(Brand.Fonts.body(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: binding(for: spec.name))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { settings.isToolEnabled(name) },
            set: { settings.setToolEnabled($0, name: name) }
        )
    }
}
