import Foundation
import Observation

/// Owns the assistant's long-term memories. Persisted as a single JSON file so
/// they survive relaunches; surfaced both to the memory tools (read/write) and
/// to the chat as an injected system prompt.
@Observable
@MainActor
final class MemoryStore {
    private(set) var memories: [Memory] = []

    @ObservationIgnored private let fileURL: URL

    /// Keeps the injected prompt bounded so a long memory list can't crowd out
    /// the conversation; older memories beyond this many are dropped from the
    /// injected context (but still readable via the tools).
    private static let maxInjected = 50

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
    var promptContext: String? {
        guard !memories.isEmpty else { return nil }
        let lines = memories
            .suffix(Self.maxInjected)
            .map { "- \($0.title) : \($0.content)" }
            .joined(separator: "\n")
        return """
        Mémoire à long terme sur l'utilisateur et les tâches en cours. \
        Tiens-en compte sans la répéter mot à mot :
        \(lines)
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
