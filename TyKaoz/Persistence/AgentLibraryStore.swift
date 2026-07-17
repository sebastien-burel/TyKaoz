import Foundation
import TyKaozKit
import Observation

/// The single folder of JavaScript library files an agent may `import`. Stored
/// as one security-scoped bookmark so access survives relaunches under the
/// sandbox. Mirrors `FileSpaceStore`, but for a single folder.
@Observable
@MainActor
final class AgentLibraryStore {
    private(set) var bookmark: Data?

    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = AgentLibraryStore.defaultFileURL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        bookmark = try? Data(contentsOf: fileURL)
    }

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appending(path: "TyKaoz/agent-libraries.bookmark")
    }

    /// Point the libraries folder at `url`, persisting a security-scoped bookmark.
    func setFolder(_ url: URL) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        bookmark = data
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        bookmark = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// The current folder for display ("open in Finder", settings label).
    var folderURL: URL? { resolvedFolder() }

    /// Relative paths of the importable `.js` / `.mjs` files under the folder
    /// (e.g. `prompts.js`, `math/vec.js`), sorted. Empty if no folder is set or
    /// none are found. For the Agents UI to show what an agent can `import`.
    func moduleFiles() -> [String] {
        guard let root = resolvedFolder() else { return [] }
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }

        let rootPath = root.standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }

        var result: [String] = []
        for case let url as URL in walker {
            let ext = url.pathExtension.lowercased()
            guard ext == "js" || ext == "mjs" else { continue }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(rootPath + "/") {
                result.append(String(path.dropFirst(rootPath.count + 1)))
            }
        }
        return result.sorted()
    }

    /// Resolve the bookmark to a URL (refreshing it if stale). The caller must
    /// `startAccessingSecurityScopedResource()` before reading and stop after.
    func resolvedFolder() -> URL? {
        guard let bookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                self.bookmark = fresh
                try? fresh.write(to: fileURL, options: .atomic)
            }
        }
        return url
    }
}
