import SwiftUI

/// Minimal Phase 7 surface for the Wiki LLM feature: master toggle,
/// status line, embedding model + dimension, manual re-index button.
/// A graph viewer and a per-page reader come later.
struct WikiSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WikiManager.self) private var wiki

    @State private var reindexing = false
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
                }
            }

            if settings.wikiEnabled {
                Section("Modèle d'embedding") {
                    TextField(
                        "Identifiant du modèle Ollama",
                        text: $settings.wikiEmbeddingModelID,
                        prompt: Text("nomic-embed-text, bge-m3, mxbai-embed-large…")
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
                    .disabled(reindexing || wiki.state.context == nil)

                    if let at = lastReindexAt {
                        Text("Dernière indexation : \(at.formatted(date: .omitted, time: .standard))")
                            .font(Brand.Fonts.body(11))
                            .foregroundStyle(.secondary)
                    }
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
