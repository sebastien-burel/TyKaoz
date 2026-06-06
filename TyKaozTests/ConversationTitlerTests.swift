import Foundation
import Testing
@testable import TyKaoz

struct ConversationTitlerTests {

    @Test
    func trimsWhitespace() {
        #expect(ConversationTitler.clean("  Bonjour  ") == "Bonjour")
        #expect(ConversationTitler.clean("\nUn titre\n") == "Un titre")
    }

    @Test
    func stripsLeadingTitrePrefix() {
        #expect(ConversationTitler.clean("Titre : Exploration MLX") == "Exploration MLX")
        #expect(ConversationTitler.clean("Titre: Exploration MLX") == "Exploration MLX")
        #expect(ConversationTitler.clean("Title: MLX exploration") == "MLX exploration")
    }

    @Test
    func stripsSurroundingQuotes() {
        #expect(ConversationTitler.clean("\"Salut\"") == "Salut")
        #expect(ConversationTitler.clean("« Hello »") == "Hello")
        #expect(ConversationTitler.clean("\u{201C}Quoted\u{201D}") == "Quoted")
    }

    @Test
    func stripsTrailingPunctuation() {
        #expect(ConversationTitler.clean("Bonjour !") == "Bonjour")
        #expect(ConversationTitler.clean("Exploration MLX.") == "Exploration MLX")
        #expect(ConversationTitler.clean("Test ???") == "Test")
    }

    @Test
    func capsLengthAt60() {
        let raw = String(repeating: "a", count: 100)
        let cleaned = ConversationTitler.clean(raw)
        #expect(cleaned.count == 60)
    }

    @Test
    func returnsEmptyForEmptyInput() {
        #expect(ConversationTitler.clean("") == "")
        #expect(ConversationTitler.clean("   ") == "")
    }
}
