import Foundation
import Testing
@testable import TyKaoz

/// Covers the image-attachment path for VLM models: persistence of the
/// bytes, cleanup on delete, and that a user message's image URLs are
/// carried through to the MLX `UserInput`.
@MainActor
@Suite(.serialized)
struct MLXChatImageAttachmentTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "TyKaoz.tests.\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test
    func savesAndResolvesAttachment() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        let convID = UUID()
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        let attachment = try #require(store.saveAttachment(bytes, conversationID: convID, ext: "jpg"))

        let url = store.attachmentURL(conversationID: convID, attachment)
        #expect(attachment.filename.hasSuffix(".jpg"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect((try? Data(contentsOf: url)) == bytes)
    }

    @Test
    func deleteRemovesAttachments() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConversationStore(directory: dir, saveDelay: .milliseconds(0))
        var conv = Conversation(title: "x")
        let attachment = try #require(store.saveAttachment(Data([0xAA]), conversationID: conv.id, ext: "jpg"))
        conv.messages.append(Message(role: .user, content: "", attachments: [attachment]))
        store.add(conv)
        await store.flushPendingSaves()

        let url = store.attachmentURL(conversationID: conv.id, attachment)
        #expect(FileManager.default.fileExists(atPath: url.path))

        store.delete(id: conv.id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func attachmentsRoundTripThroughCodable() throws {
        var conv = Conversation(title: "x")
        let attachment = Message.Attachment(filename: "\(UUID().uuidString).jpg")
        conv.messages.append(Message(role: .user, content: "regarde", attachments: [attachment]))

        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        #expect(decoded.messages.first?.attachments == [attachment])
    }

    @Test
    func userMessageImageURLsReachUserInput() {
        let messages = [
            ChatMessage(role: .system, content: "sys"),
            ChatMessage(role: .user, content: "décris", imageURLs: [URL(fileURLWithPath: "/tmp/a.jpg")]),
            ChatMessage(role: .assistant, content: "ok"),
        ]
        #expect(MLXChatActor.mappedImageCountsForTests(messages) == [0, 1, 0])
    }

    // Gemma 4 (mlx-swift-lm) only supports one image per prompt, so a
    // message with several is capped to one.
    @Test
    func capsMultipleImagesInOneMessageToOne() {
        let messages = [
            ChatMessage(role: .user, content: "deux", imageURLs: [
                URL(fileURLWithPath: "/tmp/a.jpg"),
                URL(fileURLWithPath: "/tmp/b.jpg"),
            ])
        ]
        #expect(MLXChatActor.mappedImageCountsForTests(messages) == [1])
    }

    // Across turns, only the most recent image is kept (older ones, which
    // would push the prompt past one image, are dropped).
    @Test
    func keepsOnlyMostRecentImageAcrossHistory() {
        let messages = [
            ChatMessage(role: .user, content: "img1", imageURLs: [URL(fileURLWithPath: "/tmp/1.jpg")]),
            ChatMessage(role: .assistant, content: "desc1"),
            ChatMessage(role: .user, content: "img2", imageURLs: [URL(fileURLWithPath: "/tmp/2.jpg")]),
        ]
        #expect(MLXChatActor.mappedImageCountsForTests(messages) == [0, 0, 1])
    }
}
