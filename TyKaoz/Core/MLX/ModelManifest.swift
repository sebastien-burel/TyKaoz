import Foundation
import TyKaozKit

/// Domain types for the model catalog manifest (`models.json`, schema
/// v2) published under the `TyKaoz/models-manifest` Hugging Face repo.
///
/// Forward-compatible by design: an entry whose `category` (or another
/// required field) this build doesn't understand is dropped during
/// decoding instead of failing the whole manifest, so an older client
/// keeps working when the manifest gains new model categories.
struct ModelManifest: Decodable {
    let schemaVersion: Int
    let updatedAt: String?
    let models: [CatalogModel]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case models
    }

    init(schemaVersion: Int, updatedAt: String?, models: [CatalogModel]) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.models = models
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        // Lossy element decode: a malformed or unknown-category entry is
        // skipped rather than aborting the whole array.
        let lossy = try c.decode([Lossy<CatalogModel>].self, forKey: .models)
        models = lossy.compactMap(\.value)
    }
}

/// Decodes `T` when possible, otherwise holds `nil` without throwing —
/// lets one bad array element be skipped instead of failing the decode.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// One model entry. Common fields are always present; category-specific
/// fields are optional — embedding carries `dimension`/`maxSeqLen`, chat
/// carries `contextLength`/`modalities`/`paramsTotal`/`paramsActive`.
struct CatalogModel: Decodable, Identifiable, Hashable {
    enum Category: String, Decodable {
        case embedding
        case chat
    }

    let id: String                  // HuggingFace slug, e.g. "TyKaoz/bge-m3-6bit"
    let name: String
    let publisher: String?
    let description: String
    let category: Category
    let runner: String              // "mlx-lm" | "mlx-vlm" | "mlx-embeddings" | …
    let quant: String?
    let sizeBytes: Int64
    let minRamGB: Int?
    let recommendedRamGB: Int?
    let recommended: Bool
    let languages: [String]?
    /// Commit SHA the weights are pinned to, for reproducible downloads.
    let revision: String?

    // Embedding-specific
    let dimension: Int?
    let maxSeqLen: Int?

    // Chat-specific
    let contextLength: Int?
    let modalities: [String]?
    let paramsTotal: Double?
    let paramsActive: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, publisher, description, category, runner, quant
        case sizeBytes = "size_bytes"
        case minRamGB = "min_ram_gb"
        case recommendedRamGB = "recommended_ram_gb"
        case recommended, languages, revision, dimension
        case maxSeqLen = "max_seq_len"
        case contextLength = "context_length"
        case modalities
        case paramsTotal = "params_total"
        case paramsActive = "params_active"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Required — absence (or an unknown `category`) drops the entry.
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(Category.self, forKey: .category)
        // Tolerated — defaults keep a still-usable entry alive.
        publisher = try c.decodeIfPresent(String.self, forKey: .publisher)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        runner = try c.decodeIfPresent(String.self, forKey: .runner) ?? ""
        quant = try c.decodeIfPresent(String.self, forKey: .quant)
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        minRamGB = try c.decodeIfPresent(Int.self, forKey: .minRamGB)
        recommendedRamGB = try c.decodeIfPresent(Int.self, forKey: .recommendedRamGB)
        recommended = try c.decodeIfPresent(Bool.self, forKey: .recommended) ?? false
        languages = try c.decodeIfPresent([String].self, forKey: .languages)
        revision = try c.decodeIfPresent(String.self, forKey: .revision)
        dimension = try c.decodeIfPresent(Int.self, forKey: .dimension)
        maxSeqLen = try c.decodeIfPresent(Int.self, forKey: .maxSeqLen)
        contextLength = try c.decodeIfPresent(Int.self, forKey: .contextLength)
        modalities = try c.decodeIfPresent([String].self, forKey: .modalities)
        paramsTotal = try c.decodeIfPresent(Double.self, forKey: .paramsTotal)
        paramsActive = try c.decodeIfPresent(Double.self, forKey: .paramsActive)
    }

    /// VLM entries carry an `image` modality and load through
    /// `VLMModelFactory` instead of `LLMModelFactory`.
    var isVision: Bool { modalities?.contains("image") ?? false }
}
