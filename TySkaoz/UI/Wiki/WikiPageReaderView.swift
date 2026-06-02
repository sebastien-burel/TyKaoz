import SwiftUI
import GRDB
import MarkdownUI

/// Renders a wiki page: front matter strip, markdown body, clickable
/// wikilinks that navigate within the same browser window.
struct WikiPageReaderView: View {
    let pageRef: WikiPageRef
    let context: WikiContext
    @Binding var selection: WikiPageRef?

    @Environment(WikiManager.self) private var wiki

    @State private var content: String = ""
    @State private var loadingError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let error = loadingError {
                    Text(error)
                        .font(Brand.Fonts.body(12))
                        .foregroundStyle(.red)
                } else {
                    bodyView
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Brand.Colors.paper)
        .task(id: pageRef.id) { await load() }
        .task(id: wiki.indexRevision) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pageRef.title)
                .font(Brand.Fonts.title(22))
                .foregroundStyle(Brand.Colors.ink)
            Text("id: \(pageRef.id)  ·  \(pageRef.path)")
                .font(Brand.Fonts.mono(10))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var bodyView: some View {
        Markdown(Self.rewriteWikilinksAsMarkdownLinks(stripFrontmatter(content)))
            .markdownTextStyle {
                FontFamily(.custom("Inter Tight"))
                FontSize(14)
                ForegroundColor(Brand.Colors.ink)
            }
            .markdownBlockStyle(\.paragraph) { c in
                c.label.lineSpacing(4).padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading1) { c in
                c.label.padding(.top, 8).padding(.bottom, 4)
            }
            .markdownBlockStyle(\.heading2) { c in
                c.label.padding(.top, 6).padding(.bottom, 3)
            }
            .markdownBlockStyle(\.codeBlock) { c in
                c.label
                    .padding(10)
                    .background(Brand.Colors.slate.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .markdownTextStyle {
                        FontFamily(.custom("JetBrains Mono"))
                        FontSize(12)
                    }
            }
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "wiki", let id = url.host ?? url.path.removingPercentPrefix() {
                    Task { await navigate(toID: id) }
                    return .handled
                }
                return .systemAction
            })
            .textSelection(.enabled)
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        let url = context.wikiRoot.appendingPathComponent(pageRef.path)
        do {
            content = try String(contentsOf: url, encoding: .utf8)
            loadingError = nil
        } catch {
            content = ""
            loadingError = "Lecture impossible : \(error.localizedDescription)"
        }
    }

    private func stripFrontmatter(_ text: String) -> String {
        let (_, body) = MarkdownParser.splitFrontmatter(text)
        return body
    }

    // MARK: - Wikilink navigation

    /// Resolves a wikilink target id to the corresponding page row and
    /// updates `selection`. Both id and title are tried, in that order.
    private func navigate(toID rawTarget: String) async {
        let resolved: WikiPageRef? = try? await context.pool.read { db in
            // id-exact first.
            if let row = try Row.fetchOne(db, sql: """
                SELECT id, title, path FROM pages WHERE id = ?;
            """, arguments: [rawTarget]) {
                return WikiPageRef(id: row["id"], title: row["title"], path: row["path"])
            }
            if let row = try Row.fetchOne(db, sql: """
                SELECT id, title, path FROM pages WHERE title = ?;
            """, arguments: [rawTarget]) {
                return WikiPageRef(id: row["id"], title: row["title"], path: row["path"])
            }
            return nil
        }
        if let resolved {
            selection = resolved
        }
    }

    // MARK: - Wikilink → markdown link rewrite

    /// Rewrites every `[[…]]` reference into a standard markdown
    /// `[alias](wiki://id)` link so MarkdownUI renders + dispatches it
    /// through `OpenURLAction`. Pure function for testability.
    static func rewriteWikilinksAsMarkdownLinks(_ body: String) -> String {
        let pattern = /\[\[([^\]\|]+)\|([^\]]+)\]\]|\[\[([^\]]+)\]\]/
        return body.replacing(pattern) { match in
            if let raw = match.output.1, let alias = match.output.2 {
                let id = String(raw).trimmingCharacters(in: .whitespaces)
                let label = String(alias).trimmingCharacters(in: .whitespaces)
                return "[\(label)](wiki://\(id.urlPathEncoded))"
            }
            if let raw = match.output.3 {
                let title = String(raw).trimmingCharacters(in: .whitespaces)
                return "[\(title)](wiki://\(title.urlPathEncoded))"
            }
            return String(match.output.0)
        }
    }
}

private extension String {
    var urlPathEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }

    /// MarkdownUI hands `wiki://foo` to OpenURLAction; depending on the
    /// SDK we get either `host = "foo"` or `host = nil` + `path = "/foo"`.
    /// This grabs the id part either way.
    func removingPercentPrefix() -> String? {
        let trimmed = hasPrefix("/") ? String(dropFirst()) : self
        return trimmed.removingPercentEncoding ?? trimmed
    }
}
