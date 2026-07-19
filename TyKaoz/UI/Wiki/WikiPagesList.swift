import SwiftUI
import TyKaozKit
import GRDB

/// Sidebar with a search field on top: empty query → full page list
/// sorted by `updated_at` desc; non-empty query → hybrid Finder
/// results (KNN + BM25 + graph). 250 ms debounce uses SwiftUI's
/// task cancellation: each keystroke updates `query`, the task
/// re-runs, and `Task.sleep` cancellation kicks in if the user is
/// still typing.
struct WikiPagesList: View {
    let context: WikiContext
    @Binding var selection: WikiPageRef?

    @Environment(WikiManager.self) private var wiki

    @State private var query: String = ""
    @State private var pages: [WikiPageRef] = []
    @State private var matches: [SearchMatch] = []
    @State private var searchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            Divider().background(Brand.Colors.slate.opacity(0.15))
            content
        }
        .background(Brand.Colors.paper)
        .task(id: wiki.indexRevision) { await reloadPages() }
        .task(id: query) { await runSearch() }
    }

    // MARK: - Header

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                TextField("Rechercher dans le wiki…", text: $query)
                    .textFieldStyle(.plain)
                    .font(Brand.Fonts.body(12))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Brand.Colors.slate.opacity(0.15), lineWidth: 1)
                    )
            )

            statusLine
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let error = searchError {
            Text(error)
                .font(Brand.Fonts.body(10))
                .foregroundStyle(.orange)
                .lineLimit(2)
        } else if query.isEmpty {
            Text("\(pages.count) page\(pages.count == 1 ? "" : "s")")
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
        } else {
            Text("\(matches.count) résultat\(matches.count == 1 ? "" : "s")")
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content (full list OR search matches)

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if query.isEmpty {
                    ForEach(pages) { page in
                        row(for: page, hops: nil, snippet: nil)
                    }
                } else {
                    ForEach(matches) { match in
                        row(for: match.page, hops: match.hops, snippet: match.snippet)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func row(
        for page: WikiPageRef,
        hops: Int?,
        snippet: String?
    ) -> some View {
        let isSelected = selection?.id == page.id
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(page.title)
                    .font(Brand.Fonts.body(13))
                    .foregroundStyle(Brand.Colors.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let hops, hops > 0 {
                    Text("+\(hops)")
                        .font(Brand.Fonts.mono(10))
                        .foregroundStyle(.secondary)
                }
            }
            if let snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Brand.Colors.slate.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .onTapGesture { selection = page }
    }

    // MARK: - Loading

    @MainActor
    private func reloadPages() async {
        let snapshot: [WikiPageRef] = (try? await context.pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, title, path
                FROM pages
                ORDER BY updated_at DESC, title;
            """).map {
                WikiPageRef(id: $0["id"], title: $0["title"], path: $0["path"])
            }
        }) ?? []
        pages = snapshot
    }

    @MainActor
    private func runSearch() async {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            matches = []
            searchError = nil
            return
        }
        guard let embedder = context.embedder else {
            matches = []
            searchError = "Aucun fournisseur d'embeddings configuré."
            return
        }
        // Debounce: cooperative — Task.sleep throws on cancellation,
        // and SwiftUI cancels the previous task whenever `query`
        // changes again.
        try? await Task.sleep(for: .milliseconds(250))
        if Task.isCancelled { return }

        do {
            let finder = Finder(pool: context.pool, embedder: embedder)
            let results = try await finder.search(query, limit: 25)
            // Resolve each Retrieved to a WikiPageRef so taps reuse
            // the existing selection plumbing.
            let resolved: [SearchMatch] = try await context.pool.read { db in
                try results.compactMap { r in
                    guard let row = try Row.fetchOne(db, sql: """
                        SELECT id, title, path FROM pages WHERE id = ?;
                    """, arguments: [r.pageID]) else { return nil }
                    return SearchMatch(
                        page: WikiPageRef(id: row["id"], title: row["title"], path: row["path"]),
                        hops: r.hops,
                        snippet: r.snippet
                    )
                }
            }
            matches = resolved
            searchError = nil
        } catch {
            matches = []
            searchError = error.localizedDescription
        }
    }
}

/// One row of search results, ready for the sidebar.
struct SearchMatch: Identifiable, Hashable {
    let page: WikiPageRef
    let hops: Int
    let snippet: String

    var id: String { page.id }
}
