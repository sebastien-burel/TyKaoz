import Foundation
import KaozKit
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
        // Clear any Keychain secrets this plugin owns before forgetting it.
        if let plugin = plugins.first(where: { $0.id == id }) {
            for name in secretNames(for: plugin) {
                KeychainStore.remove(account: secretAccount(pluginID: id, name: name))
            }
        }
        plugins.removeAll { $0.id == id }
        save()
    }

    /// The parsed manifest for a stored plugin, or nil if it no longer parses.
    func manifest(for plugin: StoredPlugin) -> PluginManifest? {
        try? PluginManifest(data: Data(plugin.manifestJSON.utf8))
    }

    // MARK: - Secrets

    /// The distinct secret placeholder names a plugin declares across its
    /// tools (`***NAME***` markers in URLs/headers).
    func secretNames(for plugin: StoredPlugin) -> [String] {
        guard let manifest = manifest(for: plugin) else { return [] }
        return Set(manifest.tools.flatMap { $0.secretNames }).sorted()
    }

    func secret(for plugin: StoredPlugin, name: String) -> String {
        KeychainStore.get(account: secretAccount(pluginID: plugin.id, name: name)) ?? ""
    }

    func setSecret(_ value: String, for plugin: StoredPlugin, name: String) {
        KeychainStore.set(value, account: secretAccount(pluginID: plugin.id, name: name))
    }

    private func secretAccount(pluginID: UUID, name: String) -> String {
        "plugin.\(pluginID.uuidString).\(name)"
    }

    /// Every tool exposed by every installed plugin, with secret placeholders
    /// resolved from the Keychain.
    func tools(session: URLSession = .shared) -> [any Tool] {
        plugins.flatMap { plugin -> [any Tool] in
            guard let manifest = manifest(for: plugin) else { return [] }
            return manifest.tools.map { def in
                let resolved = Dictionary(uniqueKeysWithValues: def.secretNames.map {
                    ($0, secret(for: plugin, name: $0))
                })
                return HTTPPluginTool(definition: def, secrets: resolved, session: session)
            }
        }
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
