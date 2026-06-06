import Foundation

/// A durable note the assistant chose to remember about the user or an ongoing
/// task. Memories persist across conversations and are injected into the
/// system prompt of future chats so the model stays consistent without having
/// to re-ask.
struct Memory: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var content: String
    let createdAt: Date

    init(id: UUID = UUID(), title: String, content: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
    }
}
