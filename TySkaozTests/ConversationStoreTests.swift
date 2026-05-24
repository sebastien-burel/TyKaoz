import Foundation
import Testing
@testable import TySkaoz

@MainActor
@Suite(.serialized)
struct ConversationStoreTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "TyKaoz.tests.\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test
    func loadsEmptyDirectoryAsNoConversations() {
        let dir = tempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        #expect(store.conversations.isEmpty)
    }

    @Test
    func addAndReload() async throws {
        let dir = tempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        var conv = Conversation(title: "Premier essai")
        conv.messages.append(Message(role: .user, content: "Salut"))
        conv.messages.append(Message(role: .assistant, content: "Salut !"))
        store.add(conv)

        await store.flushPendingSaves()

        let reloaded = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        #expect(reloaded.conversations.count == 1)
        #expect(reloaded.conversations.first?.title == "Premier essai")
        #expect(reloaded.conversations.first?.messages.count == 2)
        #expect(reloaded.conversations.first?.messages[0].content == "Salut")
    }

    @Test
    func renamePersists() async throws {
        let dir = tempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        let conv = Conversation(title: "Avant")
        store.add(conv)
        await store.flushPendingSaves()

        store.rename(id: conv.id, to: "Après")
        await store.flushPendingSaves()

        let reloaded = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        #expect(reloaded.conversations.first?.title == "Après")
    }

    @Test
    func renameIgnoresEmptyTitle() async throws {
        let dir = tempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        let conv = Conversation(title: "Garde-moi")
        store.add(conv)

        store.rename(id: conv.id, to: "   ")
        #expect(store.conversations.first?.title == "Garde-moi")
    }

    @Test
    func deleteRemovesFromDiskAndMemory() async throws {
        let dir = tempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        let conv = Conversation(title: "À supprimer")
        store.add(conv)
        await store.flushPendingSaves()

        let file = dir.appending(path: "\(conv.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: file.path))

        store.delete(id: conv.id)
        #expect(store.conversations.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
    }

    @Test
    func ignoresCorruptedJSONFiles() async throws {
        let dir = tempDirectory()
        defer { cleanup(dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // One valid conversation file + one garbage file.
        let store = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        let valid = Conversation(title: "Bon")
        store.add(valid)
        await store.flushPendingSaves()

        let junk = dir.appending(path: "garbage.json")
        try Data("definitely not json".utf8).write(to: junk)

        let reloaded = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        #expect(reloaded.conversations.count == 1)
        #expect(reloaded.conversations.first?.title == "Bon")
    }

    @Test
    func updatePreservesIDAndOverwrites() async throws {
        let dir = tempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        var conv = Conversation(title: "v1")
        store.add(conv)

        conv.messages.append(Message(role: .user, content: "premier"))
        store.update(conv)
        await store.flushPendingSaves()

        let reloaded = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        #expect(reloaded.conversations.count == 1)
        #expect(reloaded.conversations.first?.id == conv.id)
        #expect(reloaded.conversations.first?.messages.count == 1)
    }
}
