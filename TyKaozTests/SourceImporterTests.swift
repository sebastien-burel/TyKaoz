import Foundation
import Testing
import UniformTypeIdentifiers
@testable import TyKaoz

/// Pure logic of the source import pipeline — no Vision/PDFKit/network.
@Suite
struct SourceImporterTests {

    // MARK: - sourceMarkdown

    @Test
    func sourceMarkdownCarriesQuotedTitleAndFrontmatter() {
        let date = ISO8601DateFormatter().date(from: "2026-07-07T10:00:00Z")!
        let out = SourceImporter.sourceMarkdown(
            title: "Rapport : bilan \"2025\"",
            kind: .pdf,
            origin: "rapport.pdf",
            body: "Corps du document.",
            date: date
        )
        #expect(out.hasPrefix("---\nkind: pdf\n"))
        // Title quoted (colons are routine in web titles) and quotes escaped.
        #expect(out.contains(#"title: "Rapport : bilan \"2025\"""#))
        #expect(out.contains("origin: rapport.pdf"))
        #expect(out.contains("date: 2026-07-07"))
        #expect(out.contains("# Rapport : bilan \"2025\"\n\nCorps du document."))
    }

    // MARK: - cleanText

    @Test
    func cleanTextNormalizesWhitespace() {
        #expect(SourceImporter.cleanText("a\n\n\n\nb") == "a\n\nb")
        #expect(SourceImporter.cleanText("ligne  \nsuite\t\n") == "ligne\nsuite")
        #expect(SourceImporter.cleanText("mot\u{00A0}collé") == "mot collé")
        #expect(SourceImporter.cleanText("\n\n  \ntexte\n\n") == "texte")
        #expect(SourceImporter.cleanText("déjà\n\npropre") == "déjà\n\npropre")
    }

    // MARK: - htmlTitle

    @Test
    func htmlTitleExtractsAndDecodes() {
        #expect(SourceImporter.htmlTitle(from: "<html><title>Ma page</title></html>") == "Ma page")
        #expect(SourceImporter.htmlTitle(from: "<TITLE>Majuscules</TITLE>") == "Majuscules")
        #expect(SourceImporter.htmlTitle(from: #"<title data-x="1">Avec attribut</title>"#) == "Avec attribut")
        #expect(SourceImporter.htmlTitle(from: "<title>A &amp; B &lt;fin&gt;</title>") == "A & B <fin>")
        #expect(SourceImporter.htmlTitle(from: "<title>Sur\ndeux lignes</title>") == "Sur deux lignes")
        #expect(SourceImporter.htmlTitle(from: "<p>pas de titre</p>") == nil)
        #expect(SourceImporter.htmlTitle(from: "<title>  </title>") == nil)
    }

    // MARK: - needsOCR

    @Test
    func needsOCRDetectsThinTextLayers() {
        #expect(SourceImporter.needsOCR(pageTexts: []))
        #expect(SourceImporter.needsOCR(pageTexts: ["", ""]))
        #expect(SourceImporter.needsOCR(pageTexts: ["quelques mots", ""]))
        let prose = String(repeating: "Une phrase raisonnablement longue. ", count: 20)
        #expect(!SourceImporter.needsOCR(pageTexts: [prose, prose]))
    }

    // MARK: - recentSourceIDs

    @Test
    func recentSourcesSortedExcludingOriginalsAndBinaries() throws {
        let rawRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rawRoot) }
        let fm = FileManager.default
        try fm.createDirectory(
            at: rawRoot.appendingPathComponent("conversations"), withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: rawRoot.appendingPathComponent("originals"), withIntermediateDirectories: true
        )

        func write(_ path: String, ageSeconds: TimeInterval) throws {
            let url = rawRoot.appendingPathComponent(path)
            try "x".write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -ageSeconds)],
                ofItemAtPath: url.path
            )
        }
        try write("vieux.md", ageSeconds: 3_600)
        try write("recent.md", ageSeconds: 60)
        try write("conversations/discussion.md", ageSeconds: 600)
        try write("originals/rapport.pdf", ageSeconds: 10)   // excluded (folder)
        try write("photo.png", ageSeconds: 5)                 // excluded (binary)

        let ids = SourceImporter.recentSourceIDs(in: rawRoot)
        #expect(ids == ["recent", "conversations/discussion", "vieux"])

        // The limit caps the list, newest first.
        #expect(SourceImporter.recentSourceIDs(in: rawRoot, limit: 1) == ["recent"])
    }

    // MARK: - kind dispatch

    @Test
    func kindMapsSupportedTypes() {
        #expect(SourceImporter.kind(for: .pdf) == .pdf)
        #expect(SourceImporter.kind(for: .png) == .image)
        #expect(SourceImporter.kind(for: .jpeg) == .image)
        #expect(SourceImporter.kind(for: .heic) == .image)
        #expect(SourceImporter.kind(for: .plainText) == .markdown)
        #expect(SourceImporter.kind(for: .json) == .markdown)
        if let md = UTType(filenameExtension: "md") {
            #expect(SourceImporter.kind(for: md) == .markdown)
        }
        #expect(SourceImporter.kind(for: .mpeg4Movie) == nil)
    }
}
