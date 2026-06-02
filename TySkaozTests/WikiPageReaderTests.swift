import Foundation
import Testing
@testable import TySkaoz

@Suite
struct WikiPageReaderTests {

    @Test
    func rewritesAliasFormToMarkdownLink() {
        let input = "Voir [[phase-6|Phase 6]] et terminé."
        let out = WikiPageReaderView.rewriteWikilinksAsMarkdownLinks(input)
        #expect(out == "Voir [Phase 6](wiki://phase-6) et terminé.")
    }

    @Test
    func rewritesBareTitleFormToMarkdownLink() {
        let input = "Cf [[Une autre page]]."
        let out = WikiPageReaderView.rewriteWikilinksAsMarkdownLinks(input)
        #expect(out == "Cf [Une autre page](wiki://Une%20autre%20page).")
    }

    @Test
    func handlesMultipleLinksAndPlainText() {
        let input = "[[a|Alias A]] puis texte puis [[Bare]] et [[id-2|Alias B]]."
        let out = WikiPageReaderView.rewriteWikilinksAsMarkdownLinks(input)
        #expect(out == "[Alias A](wiki://a) puis texte puis [Bare](wiki://Bare) et [Alias B](wiki://id-2).")
    }

    @Test
    func leavesPlainMarkdownAlone() {
        let input = "Un [lien classique](https://example.com) et **rien d'autre**."
        let out = WikiPageReaderView.rewriteWikilinksAsMarkdownLinks(input)
        #expect(out == input)
    }
}
