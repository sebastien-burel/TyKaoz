import Foundation
import KaozKit
import Observation

/// Owns the assistant's pinned preferences about the user — small, stable
/// facts (name, language, answer style) always injected into context.
/// Distinct from the wiki, which holds structured knowledge and is retrieved
/// on demand. Persisted as a single JSON file; surfaced to the memory tools
/// and injected into the chat system prompt.
@Observable
@MainActor
final class MemoryStore: MemoryStoring {
    private(set) var memories: [Memory] = []

    @ObservationIgnored private let fileURL: URL

    /// Keeps the injected prompt bounded so a long memory list can't crowd out
    /// the conversation; older memories beyond this many are dropped from the
    /// injected context (but still readable via the tools).
    private static let maxInjected = 50

    /// Character ceiling on the injected block. Memory is the small,
    /// always-on "pinned preferences" layer — the wiki owns bulk knowledge —
    /// so the block stays tiny. Newest pins win; oldest are dropped from the
    /// injection (still on disk / via the tools) once the budget is hit.
    private static let maxInjectedChars = 800

    init(fileURL: URL = MemoryStore.defaultFileURL) {
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
        return support.appending(path: "TyKaoz/memories.json")
    }

    @discardableResult
    func add(title: String, content: String) -> Memory {
        let memory = Memory(title: title, content: content)
        memories.append(memory)
        save()
        return memory
    }

    func delete(id: UUID) {
        memories.removeAll { $0.id == id }
        save()
    }

    func memory(id: UUID) -> Memory? {
        memories.first { $0.id == id }
    }

    /// The system-prompt block injected into new turns, or nil when empty.
    /// This is the "pinned preferences" layer (name, language, answer style),
    /// distinct from the wiki's knowledge base — kept small and always on.
    /// Newest entries are kept first, and lines are dropped once the
    /// character budget is reached.
    var promptContext: String? {
        guard !memories.isEmpty else { return nil }
        var lines: [String] = []
        var used = 0
        // Newest first: the freshest pins survive the budget.
        for memory in memories.suffix(Self.maxInjected).reversed() {
            let line = "- \(memory.title) : \(memory.content)"
            if used + line.count > Self.maxInjectedChars, !lines.isEmpty { break }
            lines.append(line)
            used += line.count + 1
        }
        guard !lines.isEmpty else { return nil }
        return """
        Préférences et faits épinglés sur l'utilisateur (nom, langue, style de \
        réponse). Tiens-en compte sans les répéter mot à mot :
        \(lines.reversed().joined(separator: "\n"))
        """
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(memories) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([Memory].self, from: data)
        else { return }
        memories = decoded.sorted { $0.createdAt < $1.createdAt }
    }
}
