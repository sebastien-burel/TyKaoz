import SwiftUI

/// Provider-side panel for MLX. Phase A1: information-only — the
/// real model-management UI (download / size / delete) arrives in
/// Phase B. For now we point the user at the Wiki section where the
/// embedding-side of MLX is wired up.
struct MLXSettingsView: View {
    var body: some View {
        Form {
            Section("MLX (local, in-process)") {
                Text("""
                Exécution locale via Apple Silicon. Pas de serveur, pas \
                de réseau. Les modèles sont téléchargés à la demande \
                depuis HuggingFace.
                """)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(.secondary)
            }

            Section("Embeddings") {
                Text("""
                Pour utiliser MLX comme source d'embeddings du Wiki, va \
                dans **Réglages → Wiki** et bascule la source d'embedding \
                sur « MLX (in-process) ». Le premier modèle est \
                `mlx-community/bge-m3-mlx-4bit` (~337 Mo, dim 1024).
                """)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(.secondary)
            }

            Section("Chat") {
                Text("""
                Chat MLX prévu en Phase C. Un picker de modèle dédié \
                arrivera ici avec un bouton « Télécharger » et un \
                indicateur de statut.
                """)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
