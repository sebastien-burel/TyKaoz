import SwiftUI
import KaozKit
import KaozMLX

/// Minimal Phase 7 surface for the Wiki LLM feature: master toggle,
/// status line, embedding model + dimension, manual re-index button.
/// A graph viewer and a per-page reader come later.
struct WikiSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WikiManager.self) private var wiki
    @Environment(ModelCatalogService.self) private var catalog

    @State private var reindexing = false
    @State private var rebuilding = false
    @State private var lastReindexAt: Date?
    @State private var resetting = false
    @State private var confirmingReset = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Activation") {
                Toggle("Activer le Wiki LLM", isOn: $settings.wikiEnabled)
                statusRow
                if settings.wikiEnabled {
                    Toggle(
                        "Injecter le contexte wiki dans chaque conversation",
                        isOn: $settings.wikiContextEnabled
                    )
                    Text("""
                    Catalogue des pages, ajouté en contexte système pour que \
                    le modèle consulte le wiki de lui-même. Désactivé pour \
                    Apple Intelligence.
                    """)
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)

                    if settings.wikiContextEnabled {
                        Toggle(
                            "Curation automatique",
                            isOn: $settings.wikiAutoCuration
                        )
                        Text("""
                        Activé, le modèle enrichit le wiki de lui-même au fil \
                        des conversations. Désactivé (par défaut), il ne l'écrit \
                        que si tu le demandes ou via « Wikifier » — tu choisis \
                        ce qui est enregistré. La lecture reste toujours active.
                        """)
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text("Emplacement : \(WikiManager.defaultStoreRoot().path)")
                            .font(Brand.Fonts.mono(11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button {
                            NSWorkspace.shared.open(WikiManager.defaultStoreRoot())
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(.borderless)
                        .help("Ouvrir le dossier du wiki dans le Finder")
                    }
                    Text("Embedder : \(embedderSummary)")
                        .font(Brand.Fonts.mono(11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if settings.wikiEnabled {
                Section("Source d'embedding") {
                    Picker("Provider", selection: $settings.wikiEmbeddingProviderID) {
                        Text("Ollama").tag("ollama")
                        Text("Sur ce Mac").tag("mlx")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.wikiEmbeddingProviderID) { _, newValue in
                        // Each runtime has its own canonical model
                        // ID + dimension. Switching the picker resets
                        // them to known-good values so the user doesn't
                        // ship `nomic-embed-text` (Ollama tag) into an
                        // HF-bound MLX path. For MLX, prefer a catalog
                        // model that's already installed.
                        let defaults = WikiManager.EmbedderDefaults.forProvider(newValue)
                        let modelID = newValue == "mlx"
                            ? (preferredMLXEmbeddingID() ?? defaults.modelID)
                            : defaults.modelID
                        let dimension = (newValue == "mlx"
                            ? catalog.entry(forID: modelID)?.dimension : nil) ?? defaults.dimension
                        settings.wikiEmbeddingModelID = modelID
                        if settings.wikiEmbeddingDimension != dimension {
                            Task {
                                rebuilding = true
                                settings.wikiEmbeddingDimension = dimension
                                await wiki.rebuildIndex(settings: settings)
                                rebuilding = false
                            }
                        }
                    }

                    Text("""
                    Ollama réutilise l'URL du serveur Ollama. « Sur ce Mac » \
                    exécute bge-m3 directement dans l'app via Apple Silicon — \
                    pas de serveur, modèle téléchargé à la demande. Le provider \
                    de chat reste indépendant.
                    """)
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)

                    embedderLoadRow
                }

                Section("Modèle d'embedding") {
                    if settings.wikiEmbeddingProviderID == "mlx" {
                        // The MLX embedder runs a catalog model; pick from
                        // the same list as the « Modèles d'embedding »
                        // panel so the two stay in sync. Dimension follows
                        // the model.
                        Picker("Modèle", selection: mlxModelBinding) {
                            ForEach(catalog.embeddings) { model in
                                Text(mlxModelLabel(model)).tag(model.id)
                            }
                        }
                        Text("Dimension : \(settings.wikiEmbeddingDimension) (déterminée par le modèle)")
                            .font(Brand.Fonts.body(11))
                            .foregroundStyle(.secondary)
                    } else {
                        TextField(
                            "Identifiant du modèle",
                            text: $settings.wikiEmbeddingModelID,
                            prompt: Text("nomic-embed-text, bge-m3, BAAI/bge-m3…")
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(Brand.Fonts.mono(12))

                        Stepper(
                            "Dimension : \(settings.wikiEmbeddingDimension)",
                            value: $settings.wikiEmbeddingDimension,
                            in: 128...4096,
                            step: 128
                        )
                        Text("""
                        La dimension est figée à la création de la base. \
                        Changer après coup demande une migration « rebuild vectoriel » \
                        (pas encore exposée).
                        """)
                            .font(Brand.Fonts.body(11))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Indexation") {
                    Button {
                        Task {
                            reindexing = true
                            await wiki.reindexNow()
                            lastReindexAt = .now
                            reindexing = false
                        }
                    } label: {
                        if reindexing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Indexer maintenant")
                        }
                    }
                    .disabled(reindexing || rebuilding || wiki.state.context == nil)

                    if let at = lastReindexAt {
                        Text("Dernière indexation : \(at.formatted(date: .omitted, time: .standard))")
                            .font(Brand.Fonts.body(11))
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Button(role: .destructive) {
                        Task {
                            rebuilding = true
                            await wiki.rebuildIndex(settings: settings)
                            lastReindexAt = .now
                            rebuilding = false
                        }
                    } label: {
                        if rebuilding {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Reconstruction…")
                            }
                        } else {
                            Text("Reconstruire l'index")
                        }
                    }
                    .disabled(rebuilding || reindexing)
                    Text("""
                    Supprime l'index SQLite et le reconstruit depuis le \
                    markdown sur disque. Nécessaire quand la dimension \
                    d'embedding change (ex : passage de nomic-embed-text \
                    768 à bge-m3 1024).
                    """)
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)

                    Divider()

                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        if resetting {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Réinitialisation…")
                            }
                        } else {
                            Text("Réinitialiser le wiki…")
                        }
                    }
                    .disabled(resetting || rebuilding || reindexing || wiki.state.context == nil)
                    Text("""
                    Supprime toutes les pages et vide le journal. Conserve tes \
                    sources importées (raw/) et tes conventions (AGENTS.md). \
                    Réversible via git dans le dossier du wiki.
                    """)
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: healStaleMLXModelID)
        .confirmationDialog(
            "Réinitialiser le wiki ?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Supprimer toutes les pages", role: .destructive) {
                Task {
                    resetting = true
                    await wiki.resetWiki(settings: settings)
                    lastReindexAt = .now
                    resetting = false
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Toutes les pages et le journal sont supprimés. Tes sources (raw/) et conventions sont conservées. Réversible via git.")
        }
    }

    // MARK: - Embedder summary + MLX model selection

    /// Human-readable description of the active embedder for the status
    /// line: model + where it runs. Never "non configuré" once a model
    /// is set (MLX has no URL but is configured all the same).
    private var embedderSummary: String {
        let model = settings.wikiEmbeddingModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return "non configuré (choisis un modèle ci-dessous)" }
        if let url = wiki.activeEmbedderURL {
            return "\(model) · \(url.absoluteString)"
        }
        return "\(model) · sur ce Mac"
    }

    /// Selection binding for the MLX embedding picker. Writing a model id
    /// also pulls its dimension from the catalog (rebuilding only if the
    /// dimension actually changes — all bge-m3 variants are 1024).
    private var mlxModelBinding: Binding<String> {
        Binding(
            get: { settings.wikiEmbeddingModelID },
            set: { selectMLXModel($0) }
        )
    }

    private func selectMLXModel(_ id: String) {
        settings.wikiEmbeddingModelID = id
        guard let dim = catalog.entry(forID: id)?.dimension,
              dim != settings.wikiEmbeddingDimension else { return }
        Task {
            rebuilding = true
            settings.wikiEmbeddingDimension = dim
            await wiki.rebuildIndex(settings: settings)
            rebuilding = false
        }
    }

    private func mlxModelLabel(_ model: CatalogModel) -> String {
        let installed = MLXModelStore.shared.isInstalled(modelID: model.id)
        return installed ? "\(model.name) — installé" : "\(model.name) — à télécharger"
    }

    /// A catalog embedding model to default to: an already-installed one
    /// first, then the recommended/first entry.
    private func preferredMLXEmbeddingID() -> String? {
        let installed = catalog.embeddings.first { MLXModelStore.shared.isInstalled(modelID: $0.id) }
        let recommended = catalog.embeddings.first { $0.recommended }
        return (installed ?? recommended ?? catalog.embeddings.first)?.id
    }

    /// Repairs a stored MLX embedding id that isn't in the catalog (e.g.
    /// the legacy `mlx-community/bge-m3-mlx-4bit` default) by pointing it
    /// at a real catalog model — ideally the one already installed.
    private func healStaleMLXModelID() {
        guard settings.wikiEmbeddingProviderID == "mlx" else { return }
        let known = Set(catalog.embeddings.map(\.id))
        guard !known.contains(settings.wikiEmbeddingModelID),
              let preferred = preferredMLXEmbeddingID() else { return }
        selectMLXModel(preferred)
    }

    @ViewBuilder
    private var embedderLoadRow: some View {
        switch wiki.embedderLoadState {
        case .idle, .ready:
            EmptyView()
        case .downloading:
            // URLSession download tmp files live in the
            // nsurlsessiond daemon's cache outside the sandbox —
            // byte-level progress can't be observed honestly.
            // Show an indeterminate spinner instead of a fake bar.
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Téléchargement du modèle en cours…")
                    .font(Brand.Fonts.body(12))
                    .foregroundStyle(.secondary)
            }
        case .loading:
            Label("Chargement en mémoire…", systemImage: "cpu")
                .font(Brand.Fonts.body(12))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(Brand.Fonts.body(12))
                .lineLimit(4)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch wiki.state {
        case .disabled:
            Label("Désactivé", systemImage: "circle.dotted")
                .foregroundStyle(.secondary)
        case .ready:
            Label("Prêt", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(3)
        }
    }
}
