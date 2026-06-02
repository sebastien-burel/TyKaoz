import Foundation
import Testing
@testable import TySkaoz

@Suite
struct WikiLintViewTests {

    @Test
    func slugifyHandlesAccentsAndPunctuation() {
        #expect(WikiLintView.slugify("Phase 6") == "phase-6")
        #expect(WikiLintView.slugify("Élève à Paris !") == "eleve-a-paris")
        #expect(WikiLintView.slugify("RAG / Agent") == "rag-agent")
        #expect(WikiLintView.slugify("  Hello   World  ") == "hello-world")
    }

    @Test
    func slugifyFallsBackForEmptyOrPunctuationOnly() {
        let s = WikiLintView.slugify("---")
        #expect(s.hasPrefix("page-"))
    }

    @Test
    func slugifyKeepsDigits() {
        #expect(WikiLintView.slugify("GPT-4o").contains("4"))
    }
}
