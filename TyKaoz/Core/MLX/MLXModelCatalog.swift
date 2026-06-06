import Foundation

/// Curated list of MLX models known to play nicely with TyKaoz's
/// embedding pipeline. The catalog drives the management UI in
/// `MLXSettingsView` and the auto-defaults in the wiki picker.
///
/// Users can still use arbitrary HF slugs via the wiki settings
/// text field — the catalog is the easy on-ramp, not a closed list.
enum MLXModelCatalog {

    enum Kind: String {
        case embedding
        case chat   // Phase C — listed here so the catalog can grow
                    // without restructuring.
    }

    struct Entry: Identifiable, Hashable {
        let id: String           // HuggingFace slug
        let displayName: String
        let kind: Kind
        let dimension: Int?      // nil for chat models
        /// Approximate on-disk size in bytes, used for the cache
        /// pre-flight and the management UI. Refreshed loosely;
        /// HF reshards occasionally and the real number drifts.
        let sizeBytes: Int64
        /// Short, neutral, one-line description (no marketing
        /// fluff). Shown under the model name.
        let summary: String
        /// Multimodal (vision + text) when true. Loaded via
        /// `VLMModelFactory` instead of `LLMModelFactory`. Defaults
        /// to false — text-only chat models are the common case.
        let isVision: Bool

        init(
            id: String,
            displayName: String,
            kind: Kind,
            dimension: Int?,
            sizeBytes: Int64,
            summary: String,
            isVision: Bool = false
        ) {
            self.id = id
            self.displayName = displayName
            self.kind = kind
            self.dimension = dimension
            self.sizeBytes = sizeBytes
            self.summary = summary
            self.isVision = isVision
        }
    }

    /// Order matters — first entry is the recommended default for
    /// new TyKaoz installs.
    static let embeddings: [Entry] = [
        .init(
            id: "mlx-community/bge-m3-mlx-4bit",
            displayName: "BGE-M3 (4-bit)",
            kind: .embedding,
            dimension: 1024,
            sizeBytes: 337 * 1024 * 1024,
            summary: "Multilingue (100+ langues), 1024 dim. Bon défaut pour un wiki en français."
        ),
        .init(
            id: "mlx-community/bge-m3-mlx-8bit",
            displayName: "BGE-M3 (8-bit)",
            kind: .embedding,
            dimension: 1024,
            sizeBytes: 600 * 1024 * 1024,
            summary: "Même modèle qu'au-dessus, qualité un poil meilleure, le double sur disque."
        ),
        .init(
            id: "mlx-community/nomic-embed-text-v1.5-4bit",
            displayName: "Nomic Embed Text v1.5 (4-bit)",
            kind: .embedding,
            dimension: 768,
            sizeBytes: 90 * 1024 * 1024,
            summary: "Anglais-first, 768 dim. Léger — bon choix pour un Mac avec peu de RAM."
        ),
        .init(
            id: "mlx-community/bge-small-en-v1.5-4bit",
            displayName: "BGE Small EN v1.5 (4-bit)",
            kind: .embedding,
            dimension: 384,
            sizeBytes: 35 * 1024 * 1024,
            summary: "Très léger (35 Mo) mais anglais uniquement et 384 dim — qualité limitée."
        ),
    ]

    /// Chat models. First entry is the recommended default.
    static let chats: [Entry] = [
        .init(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            displayName: "Llama 3.2 3B Instruct (4-bit)",
            kind: .chat,
            dimension: nil,
            sizeBytes: 2 * 1024 * 1024 * 1024,
            summary: "Multilingue, instruction-tuned, ~2 Go. Bon défaut pour un Mac 16 Go."
        ),
        .init(
            id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            displayName: "Qwen 2.5 3B Instruct (4-bit)",
            kind: .chat,
            dimension: nil,
            sizeBytes: 2 * 1024 * 1024 * 1024,
            summary: "Bon en français + tool-calling structuré. Taille équivalente à Llama 3.2 3B."
        ),
        .init(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            displayName: "Llama 3.2 1B Instruct (4-bit)",
            kind: .chat,
            dimension: nil,
            sizeBytes: 750 * 1024 * 1024,
            summary: "Très léger (~750 Mo). Pour tester le pipeline ou un Mac 8 Go."
        ),

        // Vision-language models (VLM) — loaded via VLMModelFactory.
        // Accept text-only inputs too; image attachments arrive when
        // the chat view exposes a picker (Phase D follow-up).
        .init(
            id: "mlx-community/gemma-4-e2b-it-4bit",
            displayName: "Gemma 4 E2B Instruct (4-bit, VLM)",
            kind: .chat,
            dimension: nil,
            sizeBytes: Int64(1.5 * 1024 * 1024 * 1024),
            summary: "Multimodal léger (~1,5 Go, 2B effectifs). Idéal pour tester la pipeline VLM.",
            isVision: true
        ),
        .init(
            id: "mlx-community/gemma-4-e4b-it-4bit",
            displayName: "Gemma 4 E4B Instruct (4-bit, VLM)",
            kind: .chat,
            dimension: nil,
            sizeBytes: Int64(2.5 * 1024 * 1024 * 1024),
            summary: "Multimodal quotidien (~2,5 Go, 4B effectifs). Bon défaut VLM sur Mac 16 Go.",
            isVision: true
        ),
        .init(
            id: "mlx-community/gemma-4-26b-a4b-it-4bit",
            displayName: "Gemma 4 26B/A4B Instruct (4-bit, VLM)",
            kind: .chat,
            dimension: nil,
            sizeBytes: 13 * 1024 * 1024 * 1024,
            summary: "Multimodal sparse 26B/4B-actifs (~13 Go). Qualité supérieure, Mac 32 Go+.",
            isVision: true
        ),
    ]

    /// Lookup by HF slug. Used to enrich download progress lines and
    /// the wiki picker's auto-defaults.
    static func entry(forID id: String) -> Entry? {
        (embeddings + chats).first { $0.id == id }
    }
}
