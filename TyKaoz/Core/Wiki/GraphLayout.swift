import Foundation
import CoreGraphics

/// Pure force-directed layout of a small graph. Eades-style spring
/// model: nodes repel each other, edges spring back to a rest
/// length, a mild center pull keeps the whole thing in frame.
///
/// Runs N iterations once (no continuous animation needed for the
/// MVP browser). O(nodes²) per iteration — fine up to a few
/// hundred nodes; switch to Barnes-Hut if a real-world wiki ever
/// blows past that.
enum GraphLayout {

    struct Tunables {
        var iterations = 200
        var repulsion: Double = 6_000
        var springConstant: Double = 0.04
        var springRestLength: Double = 90
        var centerPull: Double = 0.005
        var damping: Double = 0.85
        var dt: Double = 0.6
        var initialRadius: Double = 200
    }

    /// `nodes` is an ordered list of node IDs. `edges` are undirected
    /// pairs `(a, b)`. Returns a position per node id, centred on
    /// the origin.
    static func layout(
        nodes: [String],
        edges: [(String, String)],
        tunables: Tunables = .init()
    ) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        if nodes.count == 1 { return [nodes[0]: .zero] }

        // Seed positions on a circle, hash-shuffled per id for
        // determinism across runs.
        var positions = [String: CGPoint]()
        var velocities = [String: CGVector]()
        for (i, id) in nodes.enumerated() {
            let angle = 2 * .pi * Double(i) / Double(nodes.count)
            positions[id] = CGPoint(
                x: cos(angle) * tunables.initialRadius,
                y: sin(angle) * tunables.initialRadius
            )
            velocities[id] = .zero
        }

        // Deduplicate undirected edges so we don't double-spring.
        let dedupedEdges: Set<UnorderedPair> = Set(
            edges.compactMap { a, b in
                a == b ? nil : UnorderedPair(a, b)
            }
        )

        for _ in 0..<tunables.iterations {
            var forces = [String: CGVector]()
            for id in nodes { forces[id] = .zero }

            // Repulsion: every pair.
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let a = nodes[i]
                    let b = nodes[j]
                    let pa = positions[a]!
                    let pb = positions[b]!
                    var dx = pa.x - pb.x
                    var dy = pa.y - pb.y
                    var dist2 = max(1, dx * dx + dy * dy)
                    let dist = sqrt(dist2)
                    dx /= dist
                    dy /= dist
                    let mag = tunables.repulsion / dist2
                    forces[a]?.dx += dx * mag
                    forces[a]?.dy += dy * mag
                    forces[b]?.dx -= dx * mag
                    forces[b]?.dy -= dy * mag
                    _ = dist2 // silence warning
                }
            }

            // Springs along edges.
            for edge in dedupedEdges {
                guard let pa = positions[edge.a], let pb = positions[edge.b] else { continue }
                let dx = pb.x - pa.x
                let dy = pb.y - pa.y
                let dist = max(1, sqrt(dx * dx + dy * dy))
                let strain = dist - tunables.springRestLength
                let nx = dx / dist
                let ny = dy / dist
                let mag = tunables.springConstant * strain
                forces[edge.a]?.dx += nx * mag
                forces[edge.a]?.dy += ny * mag
                forces[edge.b]?.dx -= nx * mag
                forces[edge.b]?.dy -= ny * mag
            }

            // Mild pull toward the center prevents disconnected
            // sub-graphs from drifting off into infinity.
            for id in nodes {
                let p = positions[id]!
                forces[id]?.dx -= p.x * tunables.centerPull
                forces[id]?.dy -= p.y * tunables.centerPull
            }

            // Integrate.
            for id in nodes {
                var v = velocities[id]!
                v.dx = (v.dx + (forces[id]?.dx ?? 0) * tunables.dt) * tunables.damping
                v.dy = (v.dy + (forces[id]?.dy ?? 0) * tunables.dt) * tunables.damping
                velocities[id] = v
                var p = positions[id]!
                p.x += v.dx * tunables.dt
                p.y += v.dy * tunables.dt
                positions[id] = p
            }
        }
        return positions
    }
}

/// Hashable unordered pair for edge dedup.
private struct UnorderedPair: Hashable {
    let a: String
    let b: String
    init(_ x: String, _ y: String) {
        if x <= y { a = x; b = y } else { a = y; b = x }
    }
}
