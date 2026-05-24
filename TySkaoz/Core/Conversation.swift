import Foundation

struct Conversation: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    var messages: [Message]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        messages: [Message] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.messages = messages
    }
}
