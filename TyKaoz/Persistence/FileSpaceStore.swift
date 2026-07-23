import Foundation
import KaozKit
import Observation

/// Owns the folders the user has authorised for the file tools. Each space is
/// a security-scoped bookmark persisted to disk so access survives relaunches
/// under the sandbox. The store resolves bookmarks lazily into
/// `AuthorizedRoot`s for the tools, recreating any that go stale.
@Observable
@MainActor
final class FileSpaceStore {
    private(set) var spaces: [FileSpace] = []

    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = FileSpaceStore.defaultFileURL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        load()
    }

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support.appending(path: "TyKaoz/file-spaces.json")
    }

    /// Bookmarks a user-selected folder and adds it. Throws if the bookmark
    /// can't be created (e.g. the URL wasn't actually granted by the system).
    func add(url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let name = url.lastPathComponent
        // Avoid duplicate roots: replace an existing space pointing at the
        // same folder rather than stacking copies.
        if let idx = spaces.firstIndex(where: { $0.name == name && resolvedURL(for: $0)?.path == url.path }) {
            spaces[idx].bookmark = bookmark
        } else {
            spaces.append(FileSpace(name: name, bookmark: bookmark))
        }
        save()
    }

    func remove(id: UUID) {
        spaces.removeAll { $0.id == id }
        save()
    }

    /// Toggle whether an agent may `import` code from a space (opt-in: read
    /// access via the file tools does not by itself grant code execution).
    /// Turning importability off also clears the default-root mark.
    func setImportable(id: UUID, _ value: Bool) {
        guard let idx = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[idx].importable = value
        if !value { spaces[idx].isDefaultRoot = false }
        save()
    }

    /// Mark a space as the default module root (bare `import "x"`). Exclusive —
    /// at most one space is default; setting one clears the others. A default
    /// root is necessarily importable.
    func setDefaultRoot(id: UUID, _ value: Bool) {
        guard let idx = spaces.firstIndex(where: { $0.id == id }) else { return }
        if value {
            for i in spaces.indices { spaces[i].isDefaultRoot = false }
            spaces[idx].importable = true
            spaces[idx].isDefaultRoot = true
        } else {
            spaces[idx].isDefaultRoot = false
        }
        save()
    }

    /// Resolves every space into a security-scoped root. Spaces whose bookmark
    /// can't be resolved are skipped; stale ones are refreshed in place.
    var authorizedRoots: [AuthorizedRoot] {
        spaces.compactMap { space in
            guard let url = resolvedURL(for: space) else { return nil }
            return AuthorizedRoot(name: space.name, url: url)
        }
    }

    /// Module roots for an agent run: each importable space as a named root
    /// (its folder name → `import "name/x"`), plus the space marked default
    /// also as the bare `""` root (→ `import "x"`).
    var moduleRoots: [(prefix: String, url: URL)] {
        spaces.reduce(into: []) { roots, space in
            guard space.importable, let url = resolvedURL(for: space) else { return }
            if space.isDefaultRoot { roots.append(("", url)) }
            roots.append((space.name, url))
        }
    }

    /// Resolves one space to its on-disk URL — for the UI's
    /// "open in Finder" affordance.
    func url(for space: FileSpace) -> URL? {
        resolvedURL(for: space)
    }

    // MARK: - Private

    private func resolvedURL(for space: FileSpace) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: space.bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            refreshBookmark(for: space.id, url: url)
        }
        return url
    }

    private func refreshBookmark(for id: UUID, url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        guard let fresh = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ), let idx = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[idx].bookmark = fresh
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(spaces) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([FileSpace].self, from: data)
        else { return }
        spaces = decoded
    }
}
