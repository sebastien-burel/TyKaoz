import Foundation
import Observation

@Observable
@MainActor
final class ConversationStore {
    private(set) var conversations: [Conversation] = []

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var saveTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let saveDelay: Duration

    init(
        directory: URL = ConversationStore.defaultDirectory,
        saveDelay: Duration = .milliseconds(300)
    ) {
        self.directory = directory
        self.saveDelay = saveDelay
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    nonisolated static var defaultDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support.appending(path: "TyKaoz/conversations", directoryHint: .isDirectory)
    }

    func add(_ conversation: Conversation) {
        conversations.insert(conversation, at: 0)
        scheduleSave(conversation)
    }

    /// Updates an existing conversation (or appends if unknown). Triggers a
    /// debounced save.
    func update(_ conversation: Conversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        scheduleSave(conversation)
    }

    func rename(id: UUID, to title: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversations[idx].title = trimmed
        scheduleSave(conversations[idx])
    }

    func delete(id: UUID) {
        conversations.removeAll { $0.id == id }
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        try? FileManager.default.removeItem(at: fileURL(for: id))
        try? FileManager.default.removeItem(at: attachmentsDirectory(for: id))
    }

    // MARK: - Attachments

    /// Writes attachment bytes to the conversation's sidecar folder and
    /// returns the metadata to store on the message. Returns nil if the
    /// write fails (the caller then skips the attachment rather than
    /// sending a dangling reference).
    func saveAttachment(_ data: Data, conversationID: UUID, ext: String) -> Message.Attachment? {
        let attachment = Message.Attachment(filename: "\(UUID().uuidString).\(ext)")
        let dir = attachmentsDirectory(for: conversationID)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appending(path: attachment.filename), options: .atomic)
            return attachment
        } catch {
            return nil
        }
    }

    /// Absolute file URL of an attachment on disk.
    func attachmentURL(conversationID: UUID, _ attachment: Message.Attachment) -> URL {
        attachmentsDirectory(for: conversationID).appending(path: attachment.filename)
    }

    private func attachmentsDirectory(for conversationID: UUID) -> URL {
        directory.appending(path: "attachments/\(conversationID.uuidString)", directoryHint: .isDirectory)
    }

    /// Cancels any pending debounced save and flushes immediately. Used by
    /// tests; in production the debounce is fine.
    func flushPendingSaves() async {
        let tasks = Array(saveTasks.values)
        saveTasks.removeAll()
        for task in tasks { task.cancel() }
        for conversation in conversations {
            persist(conversation)
        }
    }

    // MARK: - Private

    private func scheduleSave(_ conversation: Conversation) {
        saveTasks[conversation.id]?.cancel()
        let id = conversation.id
        saveTasks[id] = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled, let self else { return }
            guard let current = self.conversations.first(where: { $0.id == id }) else { return }
            self.persist(current)
            self.saveTasks[id] = nil
        }
    }

    private func persist(_ conversation: Conversation) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(conversation)
            try data.write(to: fileURL(for: conversation.id), options: .atomic)
        } catch {
            // Disk failures are not fatal — we keep the conversation in memory.
        }
    }

    private func load() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [Conversation] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let conv = try? decoder.decode(Conversation.self, from: data)
            else { continue }
            loaded.append(conv)
        }
        conversations = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
