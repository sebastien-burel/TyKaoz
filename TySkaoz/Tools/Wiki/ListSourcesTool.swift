import Foundation

/// Enumerates files under `raw/` — the immutable inputs to the wiki.
/// Conversations TyKaoz mirrors there automatically (Q1=(b)),
/// drag-drop imports and Apple frameworks (Q4) feed it later.
struct ListSourcesTool: Tool {
    let context: WikiContext

    let spec = ToolSpec(
        name: "list_sources",
        description: """
        Lists raw source files available to the wiki: conversation
        transcripts, imported documents, future Apple syncs. Returns
        each entry's id (filename without extension), kind (extension),
        size in bytes and last modification date so you can pick the
        most relevant ones before calling read_source.
        """,
        inputSchemaJSON: """
        {
          "type": "object",
          "properties": {
            "limit": {
              "type": "integer",
              "description": "Max entries to return (default 50)."
            },
            "kind": {
              "type": "string",
              "description": "Optional filter by extension (md, txt, pdf...)."
            }
          },
          "additionalProperties": false
        }
        """
    )

    private struct Args: Decodable {
        let limit: Int?
        let kind: String?
    }

    func execute(arguments: Data) async throws -> String {
        let args = (try? JSONDecoder().decode(Args.self, from: arguments))
            ?? Args(limit: nil, kind: nil)

        let fm = FileManager.default
        guard fm.fileExists(atPath: context.rawRoot.path) else {
            return "Aucune source : le dossier raw/ n'existe pas encore."
        }

        var entries: [(id: String, kind: String, size: Int, modified: Date)] = []
        let enumerator = fm.enumerator(
            at: context.rawRoot,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            if let kindFilter = args.kind?.lowercased(), ext != kindFilter { continue }
            let relative = url.path.replacingOccurrences(of: context.rawRoot.path + "/", with: "")
            let id = (relative as NSString).deletingPathExtension
            entries.append((
                id: id,
                kind: ext,
                size: values.fileSize ?? 0,
                modified: values.contentModificationDate ?? .distantPast
            ))
        }

        entries.sort { $0.modified > $1.modified }
        let trimmed = Array(entries.prefix(args.limit ?? 50))
        guard !trimmed.isEmpty else {
            return "Aucune source trouvée dans raw/."
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return trimmed.map { entry in
            let date = formatter.string(from: entry.modified)
            return "- \(entry.id) (\(entry.kind), \(entry.size) bytes, \(date))"
        }.joined(separator: "\n")
    }
}
