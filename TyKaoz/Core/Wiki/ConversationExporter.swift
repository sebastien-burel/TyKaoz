import Foundation
import TyKaozKit

/// Turns a conversation into an immutable raw source for the wiki
/// (`raw/conversations/<date>-<slug>.md`). Deterministic, pure formatting;
/// the ingest prompt then asks the model to distil it into wiki pages.
enum ConversationExporter {

    /// Markdown transcript: user/assistant turns only. Tool calls, tool
    /// results and error banners are plumbing — noise for ingestion.
    static func markdown(for conversation: Conversation) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        var lines: [String] = [
            "---",
            "kind: conversation",
            "title: \(conversation.title)",
            "date: \(formatter.string(from: conversation.createdAt))",
            "---",
            "",
            "# \(conversation.title)",
            ""
        ]
        for message in conversation.messages {
            switch message.role {
            case .user:
                lines.append("**Utilisateur :** \(message.content)")
                lines.append("")
            case .assistant where !message.content.isEmpty:
                lines.append("**Assistant :** \(message.content)")
                lines.append("")
            default:
                continue
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Deterministic source id for a conversation, path-relative to
    /// `raw/` without extension — the exact shape `read_source` expects.
    static func sourceID(for conversation: Conversation) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let date = formatter.string(from: conversation.createdAt)
        return "conversations/\(date)-\(Slug.make(conversation.title))"
    }

    /// Writes the transcript under `rawRoot` and returns its source id.
    /// Re-mirroring the same conversation overwrites the snapshot — same
    /// id, fresher content. Returns nil when the write fails.
    static func mirror(_ conversation: Conversation, into rawRoot: URL) -> String? {
        let id = sourceID(for: conversation)
        let url = rawRoot.appendingPathComponent("\(id).md")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try markdown(for: conversation).write(to: url, atomically: true, encoding: .utf8)
            return id
        } catch {
            return nil
        }
    }
}
