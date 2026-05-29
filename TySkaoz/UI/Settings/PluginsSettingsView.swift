import SwiftUI
import UniformTypeIdentifiers

/// Lets the user install HTTP tool plugins by dropping or importing a JSON
/// manifest. Installed plugins and the tools they expose are listed with a
/// remove action.
struct PluginsSettingsView: View {
    @Environment(PluginStore.self) private var store

    @State private var importing = false
    @State private var dropTargeted = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                dropZone
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(Brand.Fonts.body(12))
                }
                if store.plugins.isEmpty {
                    emptyState
                } else {
                    pluginList
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Brand.Colors.paper)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plugins")
                .font(Brand.Fonts.title(20))
                .foregroundStyle(Brand.Colors.ink)
            Text("""
            Ajoutez des outils externes via un manifeste JSON. Chaque outil \
            appelle une URL HTTP que vous fixez : le modèle n'en contrôle que \
            les arguments.
            """)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(.secondary)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22))
                .foregroundStyle(Brand.Colors.tide)
            Text("Glissez un manifeste .json ici")
                .font(Brand.Fonts.body(12))
                .foregroundStyle(.secondary)
            Button("Importer un manifeste…") {
                error = nil
                importing = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(dropTargeted ? Brand.Colors.tide.opacity(0.10) : Brand.Colors.slate.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    Brand.Colors.slate.opacity(dropTargeted ? 0.4 : 0.18),
                    style: StrokeStyle(lineWidth: 1, dash: [4])
                )
        )
        .onDrop(of: [.json], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(for: .json) { data, _ in
                guard let data else { return }
                Task { @MainActor in install(data) }
            }
            return true
        }
    }

    private var emptyState: some View {
        Text("Aucun plugin installé.")
            .font(Brand.Fonts.body(13))
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    private var pluginList: some View {
        VStack(spacing: 0) {
            ForEach(store.plugins) { plugin in
                let manifest = store.manifest(for: plugin)
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(manifest?.name ?? "Manifeste illisible")
                            .font(Brand.Fonts.body(13))
                            .foregroundStyle(Brand.Colors.ink)
                        Text(toolSummary(manifest))
                            .font(Brand.Fonts.body(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(role: .destructive) {
                        store.remove(id: plugin.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Retirer ce plugin")
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
    }

    private func toolSummary(_ manifest: PluginManifest?) -> String {
        guard let manifest else { return "—" }
        return manifest.tools.map(\.name).joined(separator: ", ")
    }

    // MARK: - Import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                error = "Lecture du fichier impossible."
                return
            }
            install(data)
        case .failure(let failure):
            error = failure.localizedDescription
        }
    }

    private func install(_ data: Data) {
        do {
            error = nil
            try store.add(manifestData: data)
        } catch let pluginError as PluginError {
            error = pluginError.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}
