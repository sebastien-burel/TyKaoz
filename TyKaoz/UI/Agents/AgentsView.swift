import SwiftUI
import UniformTypeIdentifiers

/// The Agents window: a sidebar list of JavaScript agents, an editor for the
/// selected one, and a run panel that drives it against the current provider,
/// tools and memory — streaming its `host.log` output into a console.
struct AgentsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AgentStore.self) private var store
    @Environment(AgentLibraryStore.self) private var libraries
    @Environment(FileSpaceStore.self) private var fileSpaces
    @Environment(MemoryStore.self) private var memory
    @Environment(PluginStore.self) private var plugins
    @Environment(WikiManager.self) private var wiki

    @State private var selection: AgentScript.ID?
    @State private var draft: AgentScript?
    @State private var input = ""
    @State private var runner = AgentRunner()
    @State private var isLibraryPickerPresented = false
    @State private var moduleList: [String] = []

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 200)
        } detail: {
            detail
                .frame(minWidth: 460, minHeight: 460)
        }
        .background(Brand.Colors.paper)
        .onAppear { syncSelection(); refreshModules() }
        .onChange(of: selection) { _, _ in loadDraft() }
        .onChange(of: store.agents) { _, _ in syncSelection() }
        .onChange(of: libraries.bookmark) { _, _ in refreshModules() }
    }

    private func refreshModules() {
        moduleList = libraries.moduleFiles()
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(store.agents) { agent in
                Text(agent.name)
                    .font(Brand.Fonts.body(13))
                    .tag(agent.id)
            }
        }
        .navigationTitle("Agents")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    let agent = store.add()
                    selection = agent.id
                } label: {
                    Image(systemName: "plus")
                }
                .help("Nouvel agent")

                Button(role: .destructive) {
                    if let id = selection {
                        store.remove(id: id)
                        selection = store.agents.first?.id
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selection == nil)
                .help("Supprimer l'agent")

                Button {
                    isLibraryPickerPresented = true
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                .help(libraries.folderURL.map { "Bibliothèques JS : \($0.path)" }
                      ?? "Choisir un dossier de bibliothèques JS (import)")
            }
        }
        .fileImporter(
            isPresented: $isLibraryPickerPresented,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result { try? libraries.setFolder(url) }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if draft != nil {
            editor
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 30))
                .foregroundStyle(Brand.Colors.tide)
            Text("Aucun agent sélectionné")
                .font(Brand.Fonts.title(18))
                .foregroundStyle(Brand.Colors.ink)
            Text("Créez un agent JavaScript pour piloter le modèle, les outils et la mémoire.")
                .font(Brand.Fonts.body(12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Créer un agent") { selection = store.add().id }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("Nom de l'agent", text: nameBinding)
                    .font(Brand.Fonts.body(14))
                    .textFieldStyle(.roundedBorder)
                Button("Enregistrer") { saveDraft() }
                    .disabled(!isDirty)
                Button {
                    runDraft()
                } label: {
                    Label("Lancer", systemImage: "play.fill")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(runner.isRunning)
            }

            Text("Script")
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
            TextEditor(text: sourceBinding)
                .font(Brand.Fonts.mono(12))
                .frame(minHeight: 200)
                .padding(6)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Brand.Colors.slate.opacity(0.18), lineWidth: 1))

            Text("Entrée (JSON ou texte, optionnel)")
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
            TextField("{ \"name\": \"Seb\" }", text: $input)
                .font(Brand.Fonts.mono(12))
                .textFieldStyle(.roundedBorder)

            librariesSection

            console
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var librariesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Bibliothèques (import)")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(libraries.folderURL == nil ? "Choisir un dossier…" : "Changer…") {
                    isLibraryPickerPresented = true
                }
                .buttonStyle(.plain)
                .font(Brand.Fonts.body(11))
                .foregroundStyle(Brand.Colors.tide)
            }

            if let folder = libraries.folderURL {
                Text(folder.path)
                    .font(Brand.Fonts.mono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if moduleList.isEmpty {
                    Text("Aucun fichier .js dans ce dossier.")
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(moduleList, id: \.self) { name in
                        Text("import { … } from \"./\(name)\"")
                            .font(Brand.Fonts.mono(10))
                            .foregroundStyle(Brand.Colors.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("Aucun dossier désigné — un agent ne peut pas encore importer de module.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.Colors.inkSoft.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Brand.Colors.slate.opacity(0.18), lineWidth: 1))
    }

    private var console: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Console")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(runner.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(Brand.Fonts.mono(11))
                            .foregroundStyle(Brand.Colors.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let result = runner.result {
                        Text("→ \(result)")
                            .font(Brand.Fonts.mono(11))
                            .foregroundStyle(Brand.Colors.tide)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = runner.errorMessage {
                        Text("✗ \(error)")
                            .font(Brand.Fonts.mono(11))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Brand.Colors.slate.opacity(0.18), lineWidth: 1))
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch runner.state {
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("En cours…").font(Brand.Fonts.body(11)).foregroundStyle(.secondary)
            }
        case .finished:
            Label("Terminé", systemImage: "checkmark.circle.fill")
                .font(Brand.Fonts.body(11)).foregroundStyle(Brand.Colors.tide)
        case .failed:
            Label("Échec", systemImage: "exclamationmark.triangle.fill")
                .font(Brand.Fonts.body(11)).foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Draft binding & actions

    private var nameBinding: Binding<String> {
        Binding(get: { draft?.name ?? "" }, set: { draft?.name = $0 })
    }

    private var sourceBinding: Binding<String> {
        Binding(get: { draft?.source ?? "" }, set: { draft?.source = $0 })
    }

    private var isDirty: Bool {
        guard let draft else { return false }
        return store.agents.first { $0.id == draft.id } != draft
    }

    private func syncSelection() {
        if selection == nil || !store.agents.contains(where: { $0.id == selection }) {
            selection = store.agents.first?.id
        }
        loadDraft()
    }

    private func loadDraft() {
        draft = store.agents.first { $0.id == selection }
    }

    private func saveDraft() {
        guard let draft else { return }
        store.update(draft)
    }

    private func runDraft() {
        guard let draft else { return }
        saveDraft()
        runner.run(
            draft, input: input,
            settings: settings, fileSpaces: fileSpaces,
            memory: memory, plugins: plugins, wiki: wiki,
            libraries: libraries)
    }
}
