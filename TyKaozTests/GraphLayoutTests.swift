import Foundation
import CoreGraphics
import Testing
@testable import TyKaoz

@Suite
struct GraphLayoutTests {

    @Test
    func emptyGraph() {
        let out = GraphLayout.layout(nodes: [], edges: [])
        #expect(out.isEmpty)
    }

    @Test
    func singleNodeLandsAtOrigin() {
        let out = GraphLayout.layout(nodes: ["solo"], edges: [])
        #expect(out["solo"] == .zero)
    }

    @Test
    func twoConnectedNodesEndUpAtAboutRestLength() {
        var tunables = GraphLayout.Tunables()
        tunables.iterations = 400  // give it time to settle
        let out = GraphLayout.layout(
            nodes: ["a", "b"],
            edges: [("a", "b")],
            tunables: tunables
        )
        let pa = out["a"]!
        let pb = out["b"]!
        let dx = pa.x - pb.x
        let dy = pa.y - pb.y
        let dist = (dx * dx + dy * dy).squareRoot()
        // Spring rest length is 90. With repulsion + spring balanced,
        // equilibrium sits in a generous band around that. 30..400
        // catches any sane numerical drift.
        #expect(dist > 30)
        #expect(dist < 400)
    }

    @Test
    func disconnectedNodesArentInfinite() {
        // No edges = pure repulsion + center pull. Center pull alone
        // is enough to keep them bounded.
        var tunables = GraphLayout.Tunables()
        tunables.iterations = 300
        let out = GraphLayout.layout(
            nodes: ["a", "b", "c", "d", "e"],
            edges: [],
            tunables: tunables
        )
        for (_, p) in out {
            #expect(p.x.isFinite)
            #expect(p.y.isFinite)
            // The system should stay within a sane bounding box —
            // certainly not millions of points away.
            #expect(abs(p.x) < 10_000)
            #expect(abs(p.y) < 10_000)
        }
    }

    @Test
    func deterministicAcrossRuns() {
        let nodes = ["a", "b", "c", "d"]
        let edges = [("a", "b"), ("b", "c"), ("c", "d")]
        let out1 = GraphLayout.layout(nodes: nodes, edges: edges)
        let out2 = GraphLayout.layout(nodes: nodes, edges: edges)
        for id in nodes {
            #expect(out1[id]?.x == out2[id]?.x)
            #expect(out1[id]?.y == out2[id]?.y)
        }
    }

    @Test
    func dedupSelfLoops() {
        // A self-loop should be silently ignored — no NaN, no
        // divergence.
        let out = GraphLayout.layout(
            nodes: ["a"],
            edges: [("a", "a")]
        )
        #expect(out["a"]?.x.isFinite == true)
        #expect(out["a"]?.y.isFinite == true)
    }
}
