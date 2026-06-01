import Foundation
import Testing
@testable import TySkaoz

@Suite
struct MarkdownParserTests {

    @Test
    func parsesFrontmatterFields() {
        let raw = """
        ---
        id: phase-6
        title: Phase 6 — RAG
        type: roadmap
        sources: [conv-1, conv-2]
        created: 2026-06-01
        updated: 2026-06-01
        ---

        # Phase 6

        Voici la phase 6.
        """
        let page = MarkdownParser.parse(raw, path: "wiki/phase-6.md")
        #expect(page.id == "phase-6")
        #expect(page.title == "Phase 6 — RAG")
        #expect(page.type == "roadmap")
        #expect(page.sources == ["conv-1", "conv-2"])
        #expect(page.createdAt != nil)
    }

    @Test
    func fallsBackWhenFrontmatterMissing() {
        let raw = "# Hello\n\nNo frontmatter."
        let page = MarkdownParser.parse(raw, path: "wiki/notes/hello.md")
        #expect(page.id == "wiki-notes-hello")
        #expect(page.title == "hello")
        #expect(page.type == nil)
        #expect(page.sources.isEmpty)
    }

    @Test
    func emptyTypeYieldsNil() {
        let raw = """
        ---
        id: x
        title: X
        type:
        ---

        Body.
        """
        let page = MarkdownParser.parse(raw, path: "wiki/x.md")
        #expect(page.type == nil)
    }

    @Test
    func contentHashChangesWithContent() {
        let a = MarkdownParser.parse("hello world", path: "p.md").contentHash
        let b = MarkdownParser.parse("hello world.", path: "p.md").contentHash
        #expect(a != b)
        #expect(a.count == 64)
    }

    @Test
    func chunkingSplitsBySection() {
        let body = """
        Intro paragraph.

        # Section A

        Content of A.

        ## Subsection A1

        Detail A1.

        # Section B

        Content of B.
        """
        let chunks = MarkdownParser.chunk(body)
        #expect(chunks.count == 4)
        #expect(chunks[0].headingPath == [])
        #expect(chunks[0].text == "Intro paragraph.")
        #expect(chunks[1].headingPath == ["Section A"])
        #expect(chunks[2].headingPath == ["Section A", "Subsection A1"])
        #expect(chunks[3].headingPath == ["Section B"])
    }

    @Test
    func extractsBothWikilinkForms() {
        let body = """
        Voir [[Phase 6]] et aussi [[abc-123|Alias]].
        Lien dans une phrase [[Autre Page]] suivi de texte.
        """
        let links = MarkdownParser.extractWikilinks(in: body)
        #expect(links.count == 3)
        #expect(links[0] == Wikilink(raw: "Phase 6", alias: nil))
        #expect(links[1] == Wikilink(raw: "abc-123", alias: "Alias"))
        #expect(links[2] == Wikilink(raw: "Autre Page", alias: nil))
    }

    @Test
    func nestedBracketsDoNotConfuseParser() {
        // A markdown link like [text](url) must not be picked up.
        let body = "[link](url) but [[real link]] yes"
        let links = MarkdownParser.extractWikilinks(in: body)
        #expect(links == [Wikilink(raw: "real link", alias: nil)])
    }

    @Test
    func endToEndParse() {
        let raw = """
        ---
        id: p1
        title: Page 1
        ---

        Intro.

        # H1

        Texte avec [[Page 2]] et [[p3|alias 3]].
        """
        let page = MarkdownParser.parse(raw, path: "wiki/p1.md")
        #expect(page.id == "p1")
        #expect(page.chunks.count == 2)
        #expect(page.wikilinks.count == 2)
        #expect(page.wikilinks[1].raw == "p3")
        #expect(page.wikilinks[1].alias == "alias 3")
        #expect(page.body.contains("# H1"))
    }
}
