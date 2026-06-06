import Foundation
import Testing
@testable import TyKaoz

@Suite
struct FileSpaceAccessTests {

    /// Builds a temp tree: <base>/space, <base>/space/sub/file.txt,
    /// <base>/secret.txt, <base>/spaceX. Returns the base.
    private func makeTree() throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: UUID().uuidString)
        try fm.createDirectory(at: base.appending(path: "space/sub"), withIntermediateDirectories: true)
        try fm.createDirectory(at: base.appending(path: "spaceX"), withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: base.appending(path: "space/sub/file.txt"))
        try Data("secret".utf8).write(to: base.appending(path: "secret.txt"))
        return base
    }

    private func root(_ url: URL) -> AuthorizedRoot {
        AuthorizedRoot(name: url.lastPathComponent, url: url)
    }

    @Test
    func allowsFileInsideRoot() throws {
        let base = try makeTree()
        let space = base.appending(path: "space")
        let target = base.appending(path: "space/sub/file.txt")
        #expect(FileSpaceAccess.containingRoot(for: target, in: [root(space)]) != nil)
    }

    @Test
    func allowsRootItself() throws {
        let base = try makeTree()
        let space = base.appending(path: "space")
        #expect(FileSpaceAccess.containingRoot(for: space, in: [root(space)]) != nil)
    }

    @Test
    func rejectsSibling() throws {
        let base = try makeTree()
        let space = base.appending(path: "space")
        let outside = base.appending(path: "secret.txt")
        #expect(FileSpaceAccess.containingRoot(for: outside, in: [root(space)]) == nil)
    }

    @Test
    func rejectsTraversalEscape() throws {
        let base = try makeTree()
        let space = base.appending(path: "space")
        let escaped = base.appending(path: "space/../secret.txt")
        #expect(FileSpaceAccess.containingRoot(for: escaped, in: [root(space)]) == nil)
    }

    @Test
    func rejectsPrefixConfusion() throws {
        let base = try makeTree()
        let space = base.appending(path: "space")
        let lookalike = base.appending(path: "spaceX/file.txt")
        // "/…/spaceX" must not be treated as inside "/…/space".
        #expect(FileSpaceAccess.containingRoot(for: lookalike, in: [root(space)]) == nil)
    }

    @Test
    func withScopedAccessThrowsOutsideRoots() throws {
        let base = try makeTree()
        let space = base.appending(path: "space")
        #expect(throws: ToolError.self) {
            try FileSpaceAccess.withScopedAccess(
                to: base.appending(path: "secret.txt").path,
                roots: [root(space)]
            ) { _ in "" }
        }
    }
}
