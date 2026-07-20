import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Converts user-provided documents into readable wiki sources. The
/// converted markdown at `raw/<slug>.md` is the canonical source the LLM
/// reads (`read_source` is text-only); the original binary is preserved
/// under `raw/originals/` as evidence. All conversion is Apple-native:
/// PDFKit (text layer), Vision (OCR fallback + images), URLSession +
/// NSAttributedString (web pages).
enum SourceImporter {

    enum Kind: String {
        case pdf, image, url, markdown
    }

    enum ImportError: Error, LocalizedError, Equatable {
        case unsupportedType(String)
        case emptyContent
        case badURL
        case http(Int)
        case notHTML(String)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let ext):
                return "Format « .\(ext) » non pris en charge (PDF, image, markdown, texte)."
            case .emptyContent:
                return "Aucun texte extrait du document (l'original a été conservé dans raw/originals/)."
            case .badURL:
                return "URL invalide."
            case .http(let status):
                return "Le serveur a répondu HTTP \(status)."
            case .notHTML(let type):
                return "Contenu « \(type) » non importable (page web ou texte attendu)."
            case .unreadable(let message):
                return "Lecture impossible : \(message)"
            }
        }
    }

    // MARK: - Entry points

    /// Imports a local file: converts it to markdown at `raw/<slug>.md`,
    /// preserves the original under `raw/originals/`, returns the source id.
    static func importFile(at url: URL, into context: WikiContext) async throws -> String {
        let ext = url.pathExtension.lowercased()
        guard let type = UTType(filenameExtension: ext), let kind = kind(for: type) else {
            throw ImportError.unsupportedType(ext)
        }
        let stem = url.deletingPathExtension().lastPathComponent
        let slug = Slug.make(stem)

        let body: String
        switch kind {
        case .pdf:
            try preserveOriginal(url, slug: slug, in: context)
            body = try await pdfMarkdownBody(at: url)
        case .image:
            try preserveOriginal(url, slug: slug, in: context)
            body = try await imageText(at: url)
        case .markdown:
            body = try String(contentsOf: url, encoding: .utf8)
        case .url:
            throw ImportError.unsupportedType(ext)   // files never map to .url
        }

        let cleaned = cleanText(body)
        guard !cleaned.isEmpty else { throw ImportError.emptyContent }
        try write(
            sourceMarkdown(title: stem, kind: kind, origin: url.lastPathComponent, body: cleaned),
            slug: slug, in: context
        )
        return slug
    }

    /// Fetches a web page, converts it to text, saves it as a source.
    static func importURL(_ url: URL, into context: WikiContext) async throws -> String {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ImportError.badURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Polite headers, same as fetch_url — some sites vary content on them.
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("TyKaoz/0.1 (macOS; +https://tykaoz.bzh)", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw ImportError.unreadable(urlError.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ImportError.unreadable("réponse non-HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ImportError.http(http.statusCode)
        }

        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let body: String
        var title: String?
        if contentType.contains("html") || contentType.isEmpty {
            let html = String(decoding: data, as: UTF8.self)
            title = htmlTitle(from: html)
            body = try await htmlToText(data)
        } else if contentType.hasPrefix("text/") {
            body = String(decoding: data, as: UTF8.self)
        } else {
            throw ImportError.notHTML(contentType)
        }

        let resolvedTitle = title ?? url.host ?? "page-web"
        let cleaned = cleanText(body)
        guard !cleaned.isEmpty else { throw ImportError.emptyContent }

        let slug = Slug.make(resolvedTitle)
        try write(
            sourceMarkdown(title: resolvedTitle, kind: .url, origin: url.absoluteString, body: cleaned),
            slug: slug, in: context
        )
        return slug
    }

    // MARK: - Pure helpers (unit-tested)

    /// Maps an incoming file type to a source kind, nil when unsupported.
    static func kind(for type: UTType) -> Kind? {
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .plainText) || type.conforms(to: .json)
            || type.preferredFilenameExtension == "md" {
            return .markdown
        }
        return nil
    }

    /// Canonical source document. `title` is quoted (web titles routinely
    /// carry `:` which would break bare YAML).
    static func sourceMarkdown(
        title: String,
        kind: Kind,
        origin: String,
        body: String,
        date: Date = .now
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let quotedTitle = "\"\(title.replacingOccurrences(of: "\"", with: "\\\""))\""
        return """
        ---
        kind: \(kind.rawValue)
        title: \(quotedTitle)
        origin: \(origin)
        date: \(formatter.string(from: date))
        ---

        # \(title)

        \(body)
        """
    }

    /// Light cleanup: NBSP → space, per-line trailing whitespace stripped,
    /// runs of 3+ newlines collapsed to a blank line, outer blank trimmed.
    static func cleanText(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.components(separatedBy: "\n")
            .map { line in
                var l = line
                while let last = l.last, last == " " || last == "\t" { l.removeLast() }
                return l
            }
            .joined(separator: "\n")
        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts `<title>` from raw HTML — pure regex so it's testable
    /// without the MainActor-bound HTML importer.
    static func htmlTitle(from html: String) -> String? {
        guard let regex = try? Regex("<title[^>]*>(.*?)</title>")
            .ignoresCase()
            .dotMatchesNewlines(),
              let match = try? regex.firstMatch(in: html),
              let raw = match.output[1].substring.map(String.init)
        else { return nil }
        let decoded = decodeEntities(raw)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    /// True when the PDF's text layer is too thin to be useful — the
    /// telltale of a scanned document that needs OCR.
    static func needsOCR(pageTexts: [String]) -> Bool {
        guard !pageTexts.isEmpty else { return true }
        let totalChars = pageTexts
            .map { $0.filter { !$0.isWhitespace }.count }
            .reduce(0, +)
        return totalChars / pageTexts.count < 120
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        for (entity, char) in [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")
        ] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }

    // MARK: - Conversions

    /// Text layer via PDFKit; OCR fallback for scanned documents.
    private static func pdfMarkdownBody(at url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ImportError.unreadable("PDF illisible")
        }
        var pageTexts: [String] = []
        for i in 0..<document.pageCount {
            pageTexts.append(document.page(at: i)?.string ?? "")
        }
        if !needsOCR(pageTexts: pageTexts) {
            return pageTexts.joined(separator: "\n\n")
        }
        // Scanned document: render each page (~180 DPI) and OCR it.
        var ocrTexts: [String] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * 2.5, height: bounds.height * 2.5)
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            ocrTexts.append(try await ocrText(from: cgImage))
        }
        return ocrTexts.joined(separator: "\n\n")
    }

    /// OCR text from an image file (png/jpeg/heic via ImageIO).
    private static func imageText(at url: URL) async throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImportError.unreadable("image illisible")
        }
        return try await ocrText(from: cgImage)
    }

    private static func ocrText(from cgImage: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [
            Locale.Language(identifier: "fr-FR"),
            Locale.Language(identifier: "en-US")
        ]
        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// HTML → readable text. The importer is WebKit-backed and documented
    /// main-thread-only; the hop is short for a typical article.
    private static func htmlToText(_ data: Data) async throws -> String {
        try await MainActor.run {
            do {
                let attributed = try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.html],
                    documentAttributes: nil
                )
                return attributed.string
            } catch {
                throw ImportError.unreadable("conversion HTML : \(error.localizedDescription)")
            }
        }
    }

    /// Most recently modified readable sources under `raw/`, as ids in the
    /// same shape `list_sources`/`read_source` use (path relative to raw/,
    /// no extension). Feeds the chat's "Wikifier" menu.
    static func recentSourceIDs(in rawRoot: URL, limit: Int = 15) -> [String] {
        let fm = FileManager.default
        let textExtensions: Set<String> = ["md", "txt", "json", "log"]
        var entries: [(id: String, modified: Date)] = []
        let enumerator = fm.enumerator(
            at: rawRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            ), values.isRegularFile == true else { continue }
            guard textExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let relative = url.path.replacingOccurrences(of: rawRoot.path + "/", with: "")
            if relative.hasPrefix("originals/") { continue }
            entries.append((
                id: (relative as NSString).deletingPathExtension,
                modified: values.contentModificationDate ?? .distantPast
            ))
        }
        return entries
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map(\.id)
    }

    // MARK: - Store I/O

    private static func preserveOriginal(_ url: URL, slug: String, in context: WikiContext) throws {
        let fm = FileManager.default
        let originals = context.rawRoot.appendingPathComponent("originals", isDirectory: true)
        try fm.createDirectory(at: originals, withIntermediateDirectories: true)
        let dest = originals.appendingPathComponent("\(slug).\(url.pathExtension.lowercased())")
        try? fm.removeItem(at: dest)
        try fm.copyItem(at: url, to: dest)
    }

    private static func write(_ markdown: String, slug: String, in context: WikiContext) throws {
        let dest = context.rawRoot.appendingPathComponent("\(slug).md")
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try markdown.write(to: dest, atomically: true, encoding: .utf8)
    }
}
