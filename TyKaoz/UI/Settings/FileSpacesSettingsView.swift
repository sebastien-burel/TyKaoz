import SwiftUI
import TyKaozKit
import UniformTypeIdentifiers

/// Lets the user grant the file tools access to local folders. Each added
/// folder is persisted as a security-scoped bookmark; the tools can only ever
/// read inside these roots.
struct FileSpacesSettingsView: View {
    @Environment(FileSpaceStore.self) private var store

    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if store.spaces.isEmpty {
                    emptyState
                } else {
                    spacesList
                }

                if let importError {
                    Label(importError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(Brand.Fonts.body(12))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Brand.Colors.paper)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dossiers autorisés")
                .font(Brand.Fonts.title(20))
                .foregroundStyle(Brand.Colors.ink)
            Text("""
            Les outils de fichiers (lister, lire, rechercher) ne peuvent accéder \
            qu'aux dossiers ajoutés ici. L'accès est en lecture seule et reste \
            actif d'une session à l'autre.
            """)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(.secondary)

            Button {
                importError = nil
                importing = true
            } label: {
                Label("Ajouter un dossier…", systemImage: "folder.badge.plus")
            }
            .padding(.top, 4)
        }
    }

    private var emptyState: some View {
        Text("Aucun dossier autorisé.")
            .font(Brand.Fonts.body(13))
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    private var spacesList: some View {
        VStack(spacing: 0) {
            ForEach(store.spaces) { space in
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Brand.Colors.tide)
                    Text(space.name)
                        .font(Brand.Fonts.body(13))
                        .foregroundStyle(Brand.Colors.ink)
                    Spacer()
                    if let url = store.url(for: space) {
                        Button {
                            // Sandbox: the folder lives outside our container,
                            // so we must hold its security-scoped access while
                            // asking Finder to reveal it.
                            let didStart = url.startAccessingSecurityScopedResource()
                            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(.borderless)
                        .help("Afficher ce dossier dans le Finder")
                    }
                    Button(role: .destructive) {
                        store.remove(id: space.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Retirer ce dossier")
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                try store.add(url: url)
            } catch {
                importError = "Impossible d'ajouter ce dossier : \(error.localizedDescription)"
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}
