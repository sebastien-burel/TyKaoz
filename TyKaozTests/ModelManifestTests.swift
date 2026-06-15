import Testing
import Foundation
@testable import TyKaoz

struct ModelManifestTests {

    /// A v2 manifest with one embedding + one chat (VLM) entry, plus two
    /// entries the client should reject without aborting: an unknown
    /// category and a malformed entry missing its `id`.
    private let mixedJSON = """
    {
      "schema_version": 2,
      "updated_at": "2026-06-07",
      "models": [
        {
          "id": "TyKaoz/bge-m3-6bit",
          "name": "BGE-M3 (6-bit)",
          "publisher": "BAAI",
          "description": "Multilingue, 1024 dim.",
          "category": "embedding",
          "runner": "mlx-embeddings",
          "quant": "6-bit",
          "min_ram_gb": 4,
          "recommended_ram_gb": 8,
          "recommended": true,
          "languages": ["fr", "en"],
          "revision": "abc123",
          "size_bytes": 461761906,
          "dimension": 1024,
          "max_seq_len": 8194
        },
        {
          "id": "TyKaoz/gemma-4-E2B-it-4bit",
          "name": "Gemma 4 E2B (4-bit, VLM)",
          "publisher": "Google",
          "description": "Multimodal léger.",
          "category": "chat",
          "runner": "mlx-vlm",
          "quant": "4-bit",
          "min_ram_gb": 8,
          "recommended": false,
          "revision": "def456",
          "size_bytes": 3550670554,
          "context_length": 131072,
          "modalities": ["text", "image"],
          "params_total": 5.1,
          "params_active": 2.3
        },
        {
          "id": "TyKaoz/some-reranker",
          "name": "Future Reranker",
          "description": "Catégorie que ce client ne connaît pas encore.",
          "category": "reranker",
          "runner": "mlx-reranker",
          "size_bytes": 123
        },
        {
          "name": "Sans identifiant",
          "category": "chat",
          "size_bytes": 999
        }
      ]
    }
    """

    @Test func decodesV2AndDropsUnknownOrMalformed() throws {
        let manifest = try JSONDecoder().decode(
            ModelManifest.self, from: Data(mixedJSON.utf8)
        )

        #expect(manifest.schemaVersion == 2)
        #expect(manifest.updatedAt == "2026-06-07")
        // The reranker (unknown category) and the id-less entry are dropped;
        // the two known entries survive.
        #expect(manifest.models.count == 2)
        #expect(manifest.models.contains { $0.id == "TyKaoz/bge-m3-6bit" })
        #expect(!manifest.models.contains { $0.category.rawValue == "reranker" })
    }

    @Test func mapsEmbeddingFields() throws {
        let manifest = try JSONDecoder().decode(
            ModelManifest.self, from: Data(mixedJSON.utf8)
        )
        let embedding = try #require(manifest.models.first { $0.category == .embedding })

        #expect(embedding.dimension == 1024)
        #expect(embedding.maxSeqLen == 8194)
        #expect(embedding.sizeBytes == 461_761_906)
        #expect(embedding.revision == "abc123")
        #expect(embedding.recommended)
        #expect(!embedding.isVision)
    }

    @Test func mapsChatFieldsAndVision() throws {
        let manifest = try JSONDecoder().decode(
            ModelManifest.self, from: Data(mixedJSON.utf8)
        )
        let chat = try #require(manifest.models.first { $0.category == .chat })

        #expect(chat.contextLength == 131072)
        #expect(chat.paramsTotal == 5.1)
        #expect(chat.paramsActive == 2.3)
        #expect(chat.isVision)   // carries the "image" modality
        #expect(chat.dimension == nil)
    }

    @Test func bundledFallbackDecodes() throws {
        // The embedded offline catalog must always parse — it's the last
        // resort when there's no cache and the network is down.
        let manifest = try JSONDecoder().decode(
            ModelManifest.self,
            from: Data(ModelCatalogService.bundledManifestJSON.utf8)
        )
        #expect(manifest.models.contains { $0.category == .embedding })
        #expect(manifest.models.contains { $0.category == .chat })
    }
}
