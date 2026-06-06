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
