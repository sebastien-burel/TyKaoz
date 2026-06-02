import SwiftUI
import GRDB

/// Top-level shell for the wiki browser window. Three-pane layout:
/// sidebar with page list (with search), detail pane that switches
/// between the page reader, the lint panel, and the graph view
/// (graph in a later commit). The mode picker at the top of the
/// sidebar swaps the detail pane.
struct WikiBrowserView: View {
    @Environment(WikiManager.self) private var wiki

    @State private var mode: WikiMode = .pages
    @State private var selection: WikiPageRef?

    var body: some View {
        switch wiki.state {
        case .disabled:
            disabledPlaceholder
        case .failed(let message):
            failurePlaceholder(message)
        case .ready(let context):
            NavigationSplitView {
                sidebar(context: context)
            } detail: {
                detail(context: context)
            }
            .background(Brand.Colors.paper)
        }
    }

    @ViewBuilder
    private func sidebar(context: WikiContext) -> some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                Text("Pages").tag(WikiMode.pages)
                Text("Audit").tag(WikiMode.lint)
                Text("Graphe").tag(WikiMode.graph)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider().background(Brand.Colors.slate.opacity(0.15))

            switch mode {
            case .pages:
                WikiPagesList(context: context, selection: $selection)
            case .lint:
                lintSidebar
            case .graph:
                graphSidebar
            }
        }
        .frame(minWidth: 220)
        .navigationTitle("Wiki")
    }

    private var lintSidebar: some View {
        sidebarHint(icon: "checklist", text: "Audit en cours dans le panneau de droite.")
    }

    private var graphSidebar: some View {
        sidebarHint(icon: "circle.hexagongrid", text: "Vue graphe à droite. Clique sur un nœud pour ouvrir la page.")
    }

    private func sidebarHint(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(Brand.Colors.tide.opacity(0.6))
            Text(text)
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Colors.paper)
    }

    @ViewBuilder
    private func detail(context: WikiContext) -> some View {
        switch mode {
        case .pages:
            if let selection {
                WikiPageReaderView(pageRef: selection, context: context, selection: $selection)
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
        case .lint:
            WikiLintView(context: context, selection: Binding(
                get: { selection },
                set: { newValue in
                    selection = newValue
                    if newValue != nil { mode = .pages }
                }
            ))
        case .graph:
            WikiGraphView(context: context, selection: Binding(
                get: { selection },
                set: { newValue in
                    selection = newValue
                    if newValue != nil { mode = .pages }
                }
            ))
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

enum WikiMode: Hashable {
    case pages
    case lint
    case graph
}
