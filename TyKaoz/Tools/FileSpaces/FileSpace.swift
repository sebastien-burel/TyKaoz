import Foundation

/// A folder the user has explicitly authorised the app to read. Persistence
/// stores a security-scoped bookmark (the sandbox requires this to regain
/// access across launches); the display name is the folder's last path
/// component, kept so the UI and tools can show something readable.
struct FileSpace: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    var bookmark: Data

    init(id: UUID = UUID(), name: String, bookmark: Data) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
    }
}

/// A resolved, security-scoped root ready to hand to the file tools. The URL
/// carries the sandbox capability; callers must bracket actual file access
/// with `start`/`stopAccessingSecurityScopedResource`.
struct AuthorizedRoot: Hashable, Sendable {
    let name: String
    let url: URL
}
