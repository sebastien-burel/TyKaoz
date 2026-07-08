import Foundation
import Testing
@testable import TyKaoz

/// Phase-A curation layer: index.md generation, log.md journaling,
/// wiki preamble assembly, summary derivation, AGENTS.md bootstrap.
@Suite(.serialized) @MainActor
struct WikiCurationTests {

    // MARK: - IndexPageGenerator

    @Test
    func generatesSortedCatalogExcludingReservedPages() {
        let entries: [IndexPageGenerator.Entry] = [
            .init(id: "zoe", title: "Zoé", summary: "Une personne."),
            .init(id: "index", title: "Index", summary: nil),
            .init(id: "log", title: "Journal", summary: nil),
            .init(id: "agents", title: "Conventions du wiki", summary: nil),
            .init(id: "arbre", title: "Arbre", summary: nil)
        ]
        let out = IndexPageGenerator.generate(entries: entries)
        #expect(out.contains("- [[arbre|Arbre]]"))
        #expect(out.contains("- [[zoe|Zoé]] — Une personne."))
        #expect(!out.contains("[[index|"))
        #expect(!out.contains("[[log|"))
        #expect(!out.contains("[[agents|"))
        // Sorted by title: Arbre before Zoé.
        let arbrePos = out.range(of: "Arbre")!.lowerBound
        let zoePos = out.range(of: "Zoé")!.lowerBound
        #expect(arbrePos < zoePos)
    }

    @Test
    func emptyWikiProducesPlaceholder() {
        let out = IndexPageGenerator.generate(entries: [])
        #expect(out.contains("*Le wiki est vide.*"))
        #expect(out.hasPrefix("---\nid: index\n"))
    }

    @Test
    func generationIsDeterministic() {
        let entries: [IndexPageGenerator.Entry] = [
            .init(id: "b", title: "B", summary: "x"),
            .init(id: "a", title: "A", summary: "y")
        ]
        #expect(IndexPageGenerator.generate(entries: entries)
            == IndexPageGenerator.generate(entries: entries.reversed()))
    }

    // MARK: - WikiLog

    @Test
    func logEntryFormat() {
        let date = ISO8601DateFormatter().date(from: "2026-07-04T10:00:00Z")!
        let line = WikiLog.entry(op: "write", detail: "Clara (clara.md)", date: date)
        #expect(line == "## [2026-07-04] write | Clara (clara.md)")
    }

    @Test
    func logAppendCreatesHeaderOnceAndAccumulates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        WikiLog.append(op: "write", detail: "A", in: dir)
        WikiLog.append(op: "ingest", detail: "B", in: dir)

        let content = try String(contentsOf: dir.appendingPathComponent("log.md"), encoding: .utf8)
        #expect(content.hasPrefix("---\nid: log\n"))
        #expect(content.contains("] write | A"))
        #expect(content.contains("] ingest | B"))
        // Header present exactly once.
        #expect(content.components(separatedBy: "id: log").count == 2)
    }

    // MARK: - WikiPromptContext

    @Test
    func preambleContainsHeaderConventionsAndCatalog() {
        let agents = "---\nid: agents\n---\n\n# Conventions\n- Une page = un sujet."
        let index = "---\nid: index\n---\n\n- [[clara|Clara]] — fille, 8 ans."
        let out = WikiPromptContext.build(agentsMD: agents, indexMD: index)
        #expect(out.contains("search_wiki"))
        #expect(out.contains("Une page = un sujet."))
        #expect(out.contains("Contenu actuel du wiki :"))
        #expect(out.contains("[[clara|Clara]]"))
        // Frontmatter stripped.
        #expect(!out.contains("id: agents"))
    }

    @Test
    func preambleTruncatesIndexBeforeConventions() {
        let agents = "---\n---\n" + String(repeating: "C", count: 1_000)
        let index = "---\n---\n" + String(repeating: "I", count: 10_000)
        let out = WikiPromptContext.build(agentsMD: agents, indexMD: index, budget: 2_000)
        // Budget respected within the fixed label overhead.
        #expect(out.count < 2_200)
        // All conventions kept, index clipped.
        #expect(out.contains(String(repeating: "C", count: 1_000)))
        #expect(!out.contains(String(repeating: "I", count: 10_000)))
    }

    @Test
    func preambleWorksWithMissingFiles() {
        let out = WikiPromptContext.build(agentsMD: nil, indexMD: nil)
        #expect(out.contains(WikiPromptContext.readHeader))
    }

    @Test
    func writePolicyFollowsAutoCurationFlag() {
        let manual = WikiPromptContext.build(agentsMD: nil, indexMD: nil, autoCuration: false)
        #expect(manual.contains("N'enrichis PAS le wiki"))
        #expect(manual.contains("Wikifier"))
        #expect(!manual.contains("Quand l'utilisateur t'apprend"))

        let auto = WikiPromptContext.build(agentsMD: nil, indexMD: nil, autoCuration: true)
        #expect(auto.contains("Quand l'utilisateur t'apprend"))
        #expect(!auto.contains("N'enrichis PAS le wiki"))
        // Reading is always instructed, regardless of mode.
        #expect(manual.contains("search_wiki"))
        #expect(auto.contains("search_wiki"))
    }

    // MARK: - Summary derivation

    @Test
    func summaryPrefersFrontmatterThenFirstProseLine() {
        let explicit = MarkdownParser.parse("""
        ---
        title: T
        summary: Résumé explicite.
        ---
        Corps.
        """, path: "t.md")
        #expect(explicit.summary == "Résumé explicite.")

        let derived = MarkdownParser.parse("""
        ---
        title: T
        ---

        # Titre de section

        Première ligne de prose.
        """, path: "t.md")
        #expect(derived.summary == "Première ligne de prose.")

        let empty = MarkdownParser.parse("---\ntitle: T\n---\n", path: "t.md")
        #expect(empty.summary == nil)
    }

    // MARK: - ConversationExporter (Phase B)

    @Test
    func transcriptKeepsOnlyUserAndAssistantTurns() {
        let conv = Conversation(
            title: "Café breton",
            createdAt: ISO8601DateFormatter().date(from: "2026-07-01T09:00:00Z")!,
            messages: [
                Message(role: .user, content: "Parle-moi du kafe."),
                Message(role: .toolCall, content: "{}", toolCallID: "c1", toolName: "search_wiki"),
                Message(role: .toolResult, content: "…", toolCallID: "c1"),
                Message(role: .assistant, content: "Le café breton…"),
                Message(role: .error, content: "boom")
            ]
        )
        let md = ConversationExporter.markdown(for: conv)
        #expect(md.contains("**Utilisateur :** Parle-moi du kafe."))
        #expect(md.contains("**Assistant :** Le café breton…"))
        #expect(!md.contains("search_wiki"))
        #expect(!md.contains("boom"))
        #expect(md.contains("title: Café breton"))
    }

    @Test
    func mirrorWritesDeterministicSourceID() throws {
        let rawRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rawRoot) }

        let conv = Conversation(
            title: "Élève à Paris !",
            createdAt: ISO8601DateFormatter().date(from: "2026-07-01T09:00:00Z")!,
            messages: [Message(role: .user, content: "x")]
        )
        let id = ConversationExporter.mirror(conv, into: rawRoot)
        #expect(id == "conversations/2026-07-01-eleve-a-paris")
        let url = rawRoot.appendingPathComponent("\(id!).md")
        #expect(FileManager.default.fileExists(atPath: url.path))
        // Re-mirroring overwrites the same snapshot, same id.
        #expect(ConversationExporter.mirror(conv, into: rawRoot) == id)
    }

    @Test
    func ingestPromptTargetsTheSource() {
        let prompt = WikiIngestPrompt.build(sourceID: "conversations/2026-07-01-cafe")
        #expect(prompt.contains("`conversations/2026-07-01-cafe`"))
        #expect(prompt.contains("read_source"))
        #expect(prompt.contains("resume-source"))
        // Keeps the model on-task and within budget: no web drift, no
        // second linking pass, no unsolicited lint.
        #expect(prompt.contains("n'utilise pas `web_search`"))
        #expect(prompt.contains("lint_wiki"))            // as a prohibition
        #expect(prompt.contains("du premier coup"))       // links in first write
        #expect(prompt.contains("Ne réécris JAMAIS"))
    }

    // MARK: - WikiLintPrompt (Phase C)

    @Test
    func lintPromptEmbedsFindingsAndAsksSemanticPass() {
        let report = LintReport(
            orphans: [.init(pageID: "solo", title: "Page seule")],
            danglingLinks: [.init(srcPageID: "a", srcTitle: "A", dstTitleRaw: "Fantôme")],
            missingConcepts: [.init(titleRaw: "RAG", references: 3)]
        )
        let prompt = WikiLintPrompt.build(report: report)
        #expect(prompt.contains("Page seule (id: solo)"))
        #expect(prompt.contains("[[Fantôme]] depuis « A »"))
        #expect(prompt.contains("« RAG » (3 références)"))
        #expect(prompt.contains("contradiction"))
        #expect(prompt.contains("write_wiki_page"))
        #expect(prompt.contains("n'utilise pas `web_search`"))
    }

    @Test
    func lintPromptStillAsksSemanticPassOnCleanReport() {
        let prompt = WikiLintPrompt.build(
            report: LintReport(orphans: [], danglingLinks: [], missingConcepts: [])
        )
        #expect(prompt.contains("rien détecté"))
        #expect(prompt.contains("passe sémantique"))
    }

    // MARK: - AGENTS.md bootstrap

    @Test
    func bootstrapCreatesSchemaFileOnceAndPreservesEdits() throws {
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let pool = try WikiDatabase.open(
            at: storeRoot.appendingPathComponent("index.sqlite"),
            embeddingDimension: 64
        )
        let ctx = WikiContext(storeRoot: storeRoot, pool: pool, embedder: nil)
        try ctx.bootstrapDirectoriesIfNeeded()

        try ctx.bootstrapSchemaFileIfNeeded()
        let url = ctx.wikiRoot.appendingPathComponent("AGENTS.md")
        #expect(FileManager.default.fileExists(atPath: url.path))

        // User edits survive a second bootstrap.
        try "custom".write(to: url, atomically: true, encoding: .utf8)
        try ctx.bootstrapSchemaFileIfNeeded()
        #expect(try String(contentsOf: url, encoding: .utf8) == "custom")
    }

    // MARK: - reindexAll regenerates index.md (fixed point)

    @Test
    func reindexRegeneratesIndexPageAndConverges() async throws {
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let pool = try WikiDatabase.open(
            at: storeRoot.appendingPathComponent("index.sqlite"),
            embeddingDimension: 64
        )
        let ctx = WikiContext(storeRoot: storeRoot, pool: pool, embedder: nil)
        try ctx.bootstrapDirectoriesIfNeeded()

        try """
        ---
        id: clara
        title: Clara
        ---
        Fille de l'utilisateur, 8 ans.
        """.write(
            to: ctx.wikiRoot.appendingPathComponent("clara.md"),
            atomically: true, encoding: .utf8
        )

        try await ctx.reindexAll()
        let indexURL = ctx.wikiRoot.appendingPathComponent("index.md")
        let first = try String(contentsOf: indexURL, encoding: .utf8)
        #expect(first.contains("[[clara|Clara]] — Fille de l'utilisateur, 8 ans."))

        // Second pass: byte-identical (fixed point), and the index page
        // itself is indexed but not listed.
        try await ctx.reindexAll()
        let second = try String(contentsOf: indexURL, encoding: .utf8)
        #expect(first == second)
        #expect(!second.contains("[[index|"))
    }
}
