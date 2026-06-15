import Foundation
import Testing
@testable import TyKaoz

struct ModelHeuristicTests {

    @Test
    func mistralChatModelsPass() {
        let chatModels = [
            "mistral-small-latest",
            "mistral-large-latest",
            "mistral-medium-2508",
            "ministral-3b-latest",
            "ministral-8b-latest",
            "codestral-latest",
            "magistral-small-latest",
            "devstral-medium-latest",
            "pixtral-large-latest"
        ]
        for id in chatModels {
            #expect(ModelHeuristic.isLikelyChatModel(id: id, provider: .mistral),
                    "expected \(id) to be considered a chat model")
        }
    }

    @Test
    func mistralNonChatModelsExcluded() {
        let nonChat = [
            "mistral-embed",
            "mistral-moderation-latest",
            "mistral-ocr-latest"
        ]
        for id in nonChat {
            #expect(!ModelHeuristic.isLikelyChatModel(id: id, provider: .mistral),
                    "expected \(id) to be excluded")
        }
    }

    @Test
    func geminiImageGenModelsPassButImagenAndDallEDoNot() {
        // Gemini image-gen runs through the chat endpoint → usable.
        #expect(ModelHeuristic.isLikelyChatModel(id: "gemini-2.5-flash-image", provider: .google))
        #expect(ModelHeuristic.isLikelyChatModel(id: "gemini-3.1-flash-image", provider: .google))
        // Imagen uses its own endpoint → stays hidden.
        #expect(!ModelHeuristic.isLikelyChatModel(id: "imagen-4.0-generate-001", provider: .google))
    }

    @Test
    func openAIImageGenModelsPass() {
        // gpt-image-1 / dall-e are usable via the Images API in the chat view.
        #expect(ModelHeuristic.isLikelyChatModel(id: "gpt-image-1", provider: .openai))
        #expect(ModelHeuristic.isLikelyChatModel(id: "dall-e-3", provider: .openai))
        // But not embeddings.
        #expect(!ModelHeuristic.isLikelyChatModel(id: "text-embedding-3-large", provider: .openai))
    }

    @Test
    func textToImageModelsPassForQwenAndZai() {
        #expect(ModelHeuristic.isLikelyChatModel(id: "qwen-image-max", provider: .qwen))
        #expect(ModelHeuristic.isLikelyChatModel(id: "cogview-4-250304", provider: .zai))
        // The exemption is provider-scoped: a "*-image" id under a provider
        // without an exemption stays hidden (the "image" hint applies).
        #expect(!ModelHeuristic.isLikelyChatModel(id: "qwen-image-max", provider: .deepseek))
    }

    @Test
    func appleAlwaysTrue() {
        #expect(ModelHeuristic.isLikelyChatModel(id: "anything", provider: .apple))
    }

    @Test
    func ollamaIncludesTypicalChatModelsExcludesEmbeds() {
        #expect(ModelHeuristic.isLikelyChatModel(id: "llama3.2:3b", provider: .ollama))
        #expect(ModelHeuristic.isLikelyChatModel(id: "qwen2.5:7b", provider: .ollama))
        #expect(!ModelHeuristic.isLikelyChatModel(id: "nomic-embed-text", provider: .ollama))
        // The heuristic is conservative — model names without a known hint
        // (e.g. "bge-m3") pass and can be disabled manually if needed.
        #expect(ModelHeuristic.isLikelyChatModel(id: "bge-m3", provider: .ollama))
    }
}
