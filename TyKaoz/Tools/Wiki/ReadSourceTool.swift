import Foundation
import TyKaozKit

/// Reads one raw source file. Text formats only — pdf, docx, etc.
/// will need their own extractor before they're agent-readable.
struct ReadSourceTool: Tool {
    let context: WikiContext

    /// Hard cap on returned bytes so a runaway file can't blow the
    /// agent's context budget. Tunable.
    static let maxReturnedBytes = 200_000

    static let textExtensions: Set<String> = ["md", "txt", "json", "log"]

    let spec = ToolSpec(
        name: "read_source",
        description: """
        Reads one raw source by its id (the filename without extension,
        as returned by list_sources). Text formats only — binary files
        such as PDFs need to be wikified manually first.
        """,
        inputSchemaJSON: """
        {
          "type": "object",
          "properties": {
            "id":   { "type": "string", "description": "Source id (path under raw/ without extension)." },
            "kind": { "type": "string", "description": "Extension if needed to disambiguate (md, txt...)." }
          },
          "required": ["id"],
          "additionalProperties": false
        }
        """
    )

    private struct Args: Decodable {
        let id: String
        let kind: String?
    }

    func execute(arguments: Data) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: arguments)
        guard !args.id.contains("..") else {
            throw ToolError.execution(message: "id invalide (sortie de raw/ refusée).")
        }

        // Resolve to a concrete file. If kind isn't given, try the
        // common text extensions in order.
        let candidates: [String] = args.kind.map { [$0] }
            ?? Self.textExtensions.sorted()
        let fm = FileManager.default
        var matched: URL?
        for ext in candidates {
            let url = context.rawRoot.appendingPathComponent("\(args.id).\(ext)")
            if fm.fileExists(atPath: url.path) {
                matched = url
                break
            }
        }
        guard let url = matched else {
            throw ToolError.execution(message: "Source introuvable pour id '\(args.id)'.")
        }

        let ext = url.pathExtension.lowercased()
        guard Self.textExtensions.contains(ext) else {
            throw ToolError.execution(
                message: "Format '\(ext)' non lisible directement. Convertis-le en markdown d'abord."
            )
        }

        let data = try Data(contentsOf: url)
        let truncated = data.prefix(Self.maxReturnedBytes)
        let content = String(decoding: truncated, as: UTF8.self)
        let note = data.count > Self.maxReturnedBytes
            ? "\n\n[…tronqué à \(Self.maxReturnedBytes) octets sur \(data.count) totaux.]"
            : ""

        let relative = url.path.replacingOccurrences(of: context.rawRoot.path + "/", with: "")
        return "--- source: \(relative)\n\n\(content)\(note)"
    }
}
