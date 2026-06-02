import SwiftUI
import GRDB

/// Sidebar that lists every page in the wiki, sorted by `updated_at`
/// desc. Reloads when `WikiManager.indexRevision` ticks (after each
/// reindex). Plain list for now — a search field replaces the static
/// header in commit B.
struct WikiPagesList: View {
    let context: WikiContext
    @Binding var selection: WikiPageRef?

    @Environment(WikiManager.self) private var wiki

    @State private var pages: [WikiPageRef] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Brand.Colors.slate.opacity(0.15))
            list
        }
        .background(Brand.Colors.paper)
        .task(id: wiki.indexRevision) { await load() }
    }

    private var header: some View {
        HStack {
            Text("\(pages.count) page\(pages.count == 1 ? "" : "s")")
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(pages) { page in
                    row(for: page)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func row(for page: WikiPageRef) -> some View {
        let isSelected = selection?.id == page.id
        return Text(page.title)
            .font(Brand.Fonts.body(13))
            .foregroundStyle(Brand.Colors.ink)
            .lineLimit(1)
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

    @MainActor
    private func load() async {
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
}
