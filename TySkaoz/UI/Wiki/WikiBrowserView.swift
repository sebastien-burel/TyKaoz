import SwiftUI
import GRDB

/// Top-level shell for the wiki browser window. Three-pane layout:
/// sidebar with page list, detail pane that switches between the
/// page reader (default), the lint panel, and the graph view (later
/// commits). Sidebar refreshes whenever the index changes via the
/// `WikiManager.indexRevision` ticker.
struct WikiBrowserView: View {
    @Environment(WikiManager.self) private var wiki

    @State private var selection: WikiPageRef?

    var body: some View {
        switch wiki.state {
        case .disabled:
            disabledPlaceholder
        case .failed(let message):
            failurePlaceholder(message)
        case .ready(let context):
            NavigationSplitView {
                WikiPagesList(context: context, selection: $selection)
                    .frame(minWidth: 220)
                    .navigationTitle("Wiki")
            } detail: {
                detail(for: selection, context: context)
            }
            .background(Brand.Colors.paper)
        }
    }

    @ViewBuilder
    private func detail(for ref: WikiPageRef?, context: WikiContext) -> some View {
        if let ref {
            WikiPageReaderView(pageRef: ref, context: context, selection: $selection)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 36))
                    .foregroundStyle(Brand.Colors.tide.opacity(0.6))
                Text("Sélectionne une page dans la sidebar.")
                    .font(Brand.Fonts.body(13))
                    .foregroundStyle(Brand.Colors.slate.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.Colors.paper)
        }
    }

    private var disabledPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 36))
                .foregroundStyle(Brand.Colors.slate.opacity(0.4))
            Text("Wiki désactivé.")
                .font(Brand.Fonts.body(14))
                .foregroundStyle(Brand.Colors.ink)
            Text("Active-le dans Réglages → Wiki.")
                .font(Brand.Fonts.body(12))
                .foregroundStyle(Brand.Colors.slate.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Colors.paper)
    }

    private func failurePlaceholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Le wiki n'a pas pu démarrer.")
                .font(Brand.Fonts.body(14))
                .foregroundStyle(Brand.Colors.ink)
            Text(message)
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Colors.paper)
    }
}

/// Stable handle for a page in the sidebar/list. Indexed by id (the
/// canonical stable key) so selection survives renames.
struct WikiPageRef: Hashable, Identifiable {
    let id: String
    let title: String
    let path: String
}
