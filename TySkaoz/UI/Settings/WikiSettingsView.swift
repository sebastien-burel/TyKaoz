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
                    }
                    .pickerStyle(.segmented)

                    Text("""
                    Réutilise l'URL configurée dans le provider \
                    correspondant (Réglages → Ollama ou Local OpenAI). \
                    Le provider sert uniquement les embeddings ici ; \
                    le provider de chat reste indépendant.
                    """)
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)
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
