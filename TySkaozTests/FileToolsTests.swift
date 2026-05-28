import Foundation
import Testing
@testable import TySkaoz

@Suite @MainActor
struct FileToolsTests {

    private func makeRoot() throws -> (root: AuthorizedRoot, base: URL) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: UUID().uuidString)
        try fm.createDirectory(at: base.appending(path: "sub"), withIntermediateDirectories: true)
        try Data("hello world\nsecond line".utf8).write(to: base.appending(path: "notes.txt"))
        try Data("needle here".utf8).write(to: base.appending(path: "sub/deep.txt"))
        return (AuthorizedRoot(name: base.lastPathComponent, url: base), base)
    }

    private func args(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - list_directory

    @Test
    func listDirectoryWithoutPathListsRoots() async throws {
        let (root, _) = try makeRoot()
        let tool = ListDirectoryTool(roots: [root])
        let output = try await tool.execute(arguments: args([:]))
        #expect(output.contains(root.name))
        #expect(output.contains(root.url.path))
    }

    @Test
    func listDirectoryListsEntries() async throws {
        let (root, base) = try makeRoot()
        let tool = ListDirectoryTool(roots: [root])
        let output = try await tool.execute(arguments: args(["path": base.path]))
        #expect(output.contains("notes.txt"))
        #expect(output.contains("sub/"))
    }

    @Test
    func listDirectoryRecursiveShowsSubtree() async throws {
        let (root, base) = try makeRoot()
        let tool = ListDirectoryTool(roots: [root])
        let output = try await tool.execute(
            arguments: args(["path": base.path, "recursive": true])
        )
        // Nested file appears with a path relative to the listed directory.
        #expect(output.contains("sub/deep.txt"))
    }

    // MARK: - read_file

    @Test
    func readFileReturnsContent() async throws {
        let (root, base) = try makeRoot()
        let tool = ReadFileTool(roots: [root])
        let output = try await tool.execute(
            arguments: args(["path": base.appending(path: "notes.txt").path])
        )
        #expect(output.contains("hello world"))
    }

    @Test
    func readFileRejectsOutsidePath() async {
        let tool = ReadFileTool(roots: [])
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: self.args(["path": "/etc/hosts"]))
        }
    }

    @Test
    func readFileTruncatesToMaxBytes() async throws {
        let (root, base) = try makeRoot()
        let tool = ReadFileTool(roots: [root])
        let output = try await tool.execute(
            arguments: args(["path": base.appending(path: "notes.txt").path, "max_bytes": 5])
        )
        #expect(output.contains("[tronqué]"))
    }

    // MARK: - grep_files

    @Test
    func grepFindsAcrossSubdirectories() async throws {
        let (root, _) = try makeRoot()
        let tool = GrepFilesTool(roots: [root])
        let output = try await tool.execute(arguments: args(["pattern": "needle"]))
        #expect(output.contains("deep.txt"))
        #expect(output.contains("needle"))
    }

    @Test
    func grepReportsNoMatch() async throws {
        let (root, _) = try makeRoot()
        let tool = GrepFilesTool(roots: [root])
        let output = try await tool.execute(arguments: args(["pattern": "zzz-nomatch-zzz"]))
        #expect(output == "Aucune correspondance.")
    }
}
