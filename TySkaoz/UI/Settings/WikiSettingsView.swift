import SwiftUI

/// Minimal Phase 7 surface for the Wiki LLM feature: master toggle,
/// status line, embedding model + dimension, manual re-index button.
/// A graph viewer and a per-page reader come later.
struct WikiSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WikiManager.self) private var wiki

    @State private var reindexing = false
    @State private var rebuilding = false
    @State private var lastReindexAt: Date?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Activation") {
                Toggle("Activer le Wiki LLM", isOn: $settings.wikiEnabled)
                statusRow
                if settings.wikiEnabled {
                    Text("Emplacement : \(WikiManager.defaultStoreRoot().path)")
                        .font(Brand.Fonts.mono(11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Embedder : \(wiki.activeEmbedderURL?.absoluteString ?? "non configuré (voir le provider ci-dessous)")")
                        .font(Brand.Fonts.mono(11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if settings.wikiEnabled {
                Section("Source d'embedding") {
                    Picker("Provider", selection: $settings.wikiEmbeddingProviderID) {
                        Text("Ollama").tag("ollama")
                        Text("Local OpenAI (vLLM, LM Studio…)").tag("localOpenAI")
                        Text("MLX (in-process)").tag("mlx")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.wikiEmbeddingProviderID) { _, newValue in
                        // Each runtime has its own canonical model
                        // ID + dimension. The text field & stepper
                        // below stay editable, but switching the
                        // picker resets them to known-good values
                        // so the user doesn't ship `nomic-embed-text`
                        // (Ollama tag) into an HF-bound MLX path.
                        let defaults = WikiManager.EmbedderDefaults.forProvider(newValue)
                        settings.wikiEmbeddingModelID = defaults.modelID
                        if settings.wikiEmbeddingDimension != defaults.dimension {
                            Task {
                                rebuilding = true
                                settings.wikiEmbeddingDimension = defaults.dimension
                                await wiki.rebuildIndex(settings: settings)
                                rebuilding = false
                            }
                        }
                    }

                    Text("""
                    Ollama / Local OpenAI réutilisent l'URL du provider \
                    correspondant. MLX exécute bge-m3 directement dans \
                    l'app via Apple Silicon — pas de serveur, modèle \
                    téléchargé à la demande. Le provider de chat reste \
                    indépendant.
                    """)
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)

                    embedderLoadRow
                }

                Section("Modèle d'embedding") {
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
                }
            }
        }
        .formStyle(.grouped)
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
