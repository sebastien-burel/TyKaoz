import SwiftUI
import GRDB
import UniformTypeIdentifiers

/// Top-level shell for the wiki browser window. Three-pane layout:
/// sidebar with page list (with search), detail pane that switches
/// between the page reader, the lint panel, and the graph view
/// (graph in a later commit). The mode picker at the top of the
/// sidebar swaps the detail pane.
struct WikiBrowserView: View {
    @Environment(WikiManager.self) private var wiki

    @State private var mode: WikiMode = .pages
    @State private var selection: WikiPageRef?
    @State private var isImporterPresented = false
    @State private var isURLImporterPresented = false
    @State private var urlInput = ""
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        switch wiki.state {
        case .disabled:
            disabledPlaceholder
        case .failed(let message):
            failurePlaceholder(message)
        case .ready(let context):
            NavigationSplitView {
                sidebar(context: context)
            } detail: {
                detail(context: context)
            }
            .background(Brand.Colors.paper)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if isImporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            isImporterPresented = true
                        } label: {
                            Label("Importer une source…", systemImage: "square.and.arrow.down")
                        }
                        .help("Convertit un fichier (PDF, image, markdown) en source lisible dans raw/")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        isURLImporterPresented = true
                    } label: {
                        Label("Importer une URL…", systemImage: "link.badge.plus")
                    }
                    .disabled(isImporting)
                    .help("Télécharge une page web et l'enregistre comme source du wiki")
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.plainText, .pdf, .json, .image]
                    + [UTType(filenameExtension: "md")].compactMap { $0 },
                allowsMultipleSelection: true
            ) { result in
                importSources(result, context: context)
            }
            .sheet(isPresented: $isURLImporterPresented) {
                urlImportSheet(context: context)
            }
            .alert(
                "Import impossible",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: - Source import

    /// Converts picked files into readable sources under `raw/` (originals
    /// preserved), then journals + commits the batch.
    private func importSources(_ result: Result<[URL], Error>, context: WikiContext) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        isImporting = true
        Task {
            var imported: [String] = []
            var failures: [String] = []
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                do {
                    imported.append(try await SourceImporter.importFile(at: url, into: context))
                } catch {
                    failures.append("\(url.lastPathComponent) : \(error.localizedDescription)")
                }
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            finishImport(imported: imported, failures: failures, context: context)
        }
    }

    private func importURL(_ raw: String, context: WikiContext) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            importError = "URL invalide."
            return
        }
        isImporting = true
        Task {
            var imported: [String] = []
            var failures: [String] = []
            do {
                imported.append(try await SourceImporter.importURL(url, into: context))
                urlInput = ""
            } catch {
                failures.append("\(trimmed) : \(error.localizedDescription)")
            }
            finishImport(imported: imported, failures: failures, context: context)
        }
    }

    private func finishImport(imported: [String], failures: [String], context: WikiContext) {
        if !imported.isEmpty {
            WikiLog.append(
                op: "ingest",
                detail: "import → raw/ : \(imported.joined(separator: ", "))",
                in: context.wikiRoot
            )
            GitRunner.commit(message: "ingest: import \(imported.joined(separator: " "))", in: context.wikiRoot)
        }
        if !failures.isEmpty {
            importError = failures.joined(separator: "\n")
        }
        isImporting = false
    }

    @ViewBuilder
    private func urlImportSheet(context: WikiContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Importer une page web")
                .font(Brand.Fonts.title(16))
                .foregroundStyle(Brand.Colors.ink)
            TextField("https://…", text: $urlInput)
                .textFieldStyle(.roundedBorder)
                .font(Brand.Fonts.mono(12))
                .frame(minWidth: 360)
                .onSubmit {
                    isURLImporterPresented = false
                    importURL(urlInput, context: context)
                }
            Text("La page est convertie en texte et enregistrée comme source du wiki.")
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Annuler") { isURLImporterPresented = false }
                Button("Importer") {
                    isURLImporterPresented = false
                    importURL(urlInput, context: context)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func sidebar(context: WikiContext) -> some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                Text("Pages").tag(WikiMode.pages)
                Text("Audit").tag(WikiMode.lint)
                Text("Graphe").tag(WikiMode.graph)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider().background(Brand.Colors.slate.opacity(0.15))

            switch mode {
            case .pages:
                WikiPagesList(context: context, selection: $selection)
            case .lint:
                lintSidebar
            case .graph:
                graphSidebar
            }
        }
        .frame(minWidth: 220)
        .navigationTitle("Wiki")
    }

    private var lintSidebar: some View {
        sidebarHint(icon: "checklist", text: "Audit en cours dans le panneau de droite.")
    }

    private var graphSidebar: some View {
        sidebarHint(icon: "circle.hexagongrid", text: "Vue graphe à droite. Clique sur un nœud pour ouvrir la page.")
    }

    private func sidebarHint(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(Brand.Colors.tide.opacity(0.6))
            Text(text)
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Colors.paper)
    }

    @ViewBuilder
    private func detail(context: WikiContext) -> some View {
        switch mode {
        case .pages:
            if let selection {
                WikiPageReaderView(pageRef: selection, context: context, selection: $selection)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 36))
                        .foregroundStyle(Brand.Colors.tide.opacity(0.6))
                    Text("Sélectionne une page dans la sidebar.")
                        .font(Brand.Fonts.body(13))
                        .foregroundStyle(Brand.Colors.slate.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Brand.Colors.paper)
            }
        case .lint:
            WikiLintView(context: context, selection: Binding(
                get: { selection },
                set: { newValue in
                    selection = newValue
                    if newValue != nil { mode = .pages }
                }
            ))
        case .graph:
            WikiGraphView(context: context, selection: Binding(
                get: { selection },
                set: { newValue in
                    selection = newValue
                    if newValue != nil { mode = .pages }
                }
            ))
        }
    }

    private var disabledPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 36))
                .foregroundStyle(Brand.Colors.slate.opacity(0.4))
            Text("Wiki désactivé.")
                .font(Brand.Fonts.body(14))
                .foregroundStyle(Brand.Colors.ink)
            Text("Active-le dans Réglages → Wiki.")
                .font(Brand.Fonts.body(12))
                .foregroundStyle(Brand.Colors.slate.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Colors.paper)
    }

    private func failurePlaceholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Le wiki n'a pas pu démarrer.")
                .font(Brand.Fonts.body(14))
                .foregroundStyle(Brand.Colors.ink)
            Text(message)
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Colors.paper)
    }
}

/// Stable handle for a page in the sidebar/list. Indexed by id (the
/// canonical stable key) so selection survives renames.
struct WikiPageRef: Hashable, Identifiable {
    let id: String
    let title: String
    let path: String
}

enum WikiMode: Hashable {
    case pages
    case lint
    case graph
}
