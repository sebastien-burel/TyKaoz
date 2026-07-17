import SwiftUI
import TyKaozKit
import GRDB

/// Force-directed graph of the wiki. Edges are drawn via Canvas
/// for cheap line rendering; nodes are SwiftUI Buttons positioned
/// with `.position()` so the existing selection plumbing (tap →
/// open page in reader) reuses without any custom hit-testing.
struct WikiGraphView: View {
    let context: WikiContext
    @Binding var selection: WikiPageRef?

    @Environment(WikiManager.self) private var wiki

    @State private var nodes: [Node] = []
    @State private var positions: [String: CGPoint] = [:]
    @State private var loading = true

    struct Node: Hashable, Identifiable {
        let id: String
        let title: String
        let path: String
        var pageRef: WikiPageRef { WikiPageRef(id: id, title: title, path: path) }
    }

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                Color(red: 247/255, green: 245/255, blue: 240/255)  // Brand.Colors.paper
                    .ignoresSafeArea()

                edgeCanvas(center: center)
                ForEach(nodes) { n in
                    nodeView(n, center: center)
                }

                if loading {
                    ProgressView("Mise en page…")
                        .controlSize(.regular)
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                } else if nodes.isEmpty {
                    Text("Aucune page dans le wiki.")
                        .font(Brand.Fonts.body(13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: wiki.indexRevision) { await rebuild() }
    }

    private func edgeCanvas(center: CGPoint) -> some View {
        Canvas { ctx, _ in
            for node in nodes {
                guard let p = positions[node.id] else { continue }
                let start = CGPoint(x: center.x + p.x, y: center.y + p.y)
                for edgeTarget in adjacency[node.id] ?? [] {
                    guard let q = positions[edgeTarget],
                          node.id < edgeTarget    // draw each undirected edge once
                    else { continue }
                    let end = CGPoint(x: center.x + q.x, y: center.y + q.y)
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    ctx.stroke(
                        path,
                        with: .color(Color(red: 45/255, green: 59/255, blue: 82/255).opacity(0.25)),
                        lineWidth: 1
                    )
                }
            }
        }
    }

    private func nodeView(_ node: Node, center: CGPoint) -> some View {
        let p = positions[node.id] ?? .zero
        let isSelected = selection?.id == node.id
        return Button {
            selection = node.pageRef
        } label: {
            Text(node.title)
                .font(Brand.Fonts.body(11))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : Color(red: 14/255, green: 20/255, blue: 32/255))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected
                            ? Color(red: 79/255, green: 184/255, blue: 201/255)   // Brand.Colors.tide
                            : Color.white)
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 45/255, green: 59/255, blue: 82/255).opacity(0.2), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .position(x: center.x + p.x, y: center.y + p.y)
    }

    // MARK: - Adjacency cache for edge drawing

    private var adjacency: [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for n in nodes { out[n.id] = [] }
        for (a, b) in edges {
            out[a, default: []].insert(b)
            out[b, default: []].insert(a)
        }
        return out
    }

    @State private var edges: [(String, String)] = []

    @MainActor
    private func rebuild() async {
        loading = true
        defer { loading = false }
        let snapshot: ([Node], [(String, String)]) = (try? await context.pool.read { db in
            let nodeRows = try Row.fetchAll(db, sql: """
                SELECT id, title, path FROM pages ORDER BY id;
            """).map {
                Node(id: $0["id"], title: $0["title"], path: $0["path"])
            }
            let edgeRows = try Row.fetchAll(db, sql: """
                SELECT src_page_id, dst_page_id FROM edges
                WHERE dst_page_id IS NOT NULL;
            """).map { row -> (String, String) in
                (row["src_page_id"], row["dst_page_id"])
            }
            return (nodeRows, edgeRows)
        }) ?? ([], [])

        nodes = snapshot.0
        edges = snapshot.1

        // Run the physics off-main so the UI can show "Mise en page…".
        let ids = snapshot.0.map(\.id)
        let edgesCopy = snapshot.1
        let computed: [String: CGPoint] = await Task.detached {
            GraphLayout.layout(nodes: ids, edges: edgesCopy)
        }.value
        positions = computed
    }
}
