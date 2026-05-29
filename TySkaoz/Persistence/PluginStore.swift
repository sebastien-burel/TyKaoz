import Foundation
import Observation

/// A persisted plugin: its raw manifest JSON plus an id. We store the raw text
/// (rather than a decoded model) so the verbatim `input_schema` survives a
/// round-trip and re-parsing stays the single source of truth.
struct StoredPlugin: Identifiable, Codable, Equatable {
    let id: UUID
    let manifestJSON: String

    init(id: UUID = UUID(), manifestJSON: String) {
        self.id = id
        self.manifestJSON = manifestJSON
    }
}

/// Owns the installed HTTP plugins. Validates manifests on add, persists them
/// to disk, and exposes the resulting tools to the registry.
@Observable
@MainActor
final class PluginStore {
    private(set) var plugins: [StoredPlugin] = []

    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = PluginStore.defaultFileURL) {
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
        return support.appending(path: "TyKaoz/plugins.json")
    }

    /// Validates the manifest, installs it, and returns the parsed result.
    /// Throws `PluginError` if the manifest is malformed.
    @discardableResult
    func add(manifestData: Data) throws -> PluginManifest {
        let manifest = try PluginManifest(data: manifestData)
        let json = String(data: manifestData, encoding: .utf8) ?? ""
        plugins.append(StoredPlugin(manifestJSON: json))
        save()
        return manifest
    }

    func remove(id: UUID) {
        plugins.removeAll { $0.id == id }
        save()
    }

    /// The parsed manifest for a stored plugin, or nil if it no longer parses.
    func manifest(for plugin: StoredPlugin) -> PluginManifest? {
        try? PluginManifest(data: Data(plugin.manifestJSON.utf8))
    }

    /// Every tool exposed by every installed plugin.
    func tools(session: URLSession = .shared) -> [any Tool] {
        plugins
            .compactMap { manifest(for: $0) }
            .flatMap(\.tools)
            .map { HTTPPluginTool(definition: $0, session: session) }
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(plugins) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([StoredPlugin].self, from: data)
        else { return }
        plugins = decoded
    }
}
