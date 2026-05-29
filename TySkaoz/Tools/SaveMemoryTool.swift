import Foundation

/// Lets the model persist a fact worth remembering across conversations.
struct SaveMemoryTool: Tool {
    let store: MemoryStore

    init(store: MemoryStore) {
        self.store = store
    }

    let spec = ToolSpec(
        name: "save_memory",
        description: """
        Saves a durable note about the user or an ongoing task so it can be
        recalled in future conversations. Use for stable facts and preferences
        (name, language, recurring context) — not for one-off chatter. Provide
        a short title and the content to remember.
        """,
        inputSchemaJSON: """
        {
          "type": "object",
          "properties": {
            "title": {
              "type": "string",
              "description": "Short label for the memory (a few words)."
            },
            "content": {
              "type": "string",
              "description": "The information to remember."
            }
          },
          "required": ["content"],
          "additionalProperties": false
        }
        """
    )

    private struct Args: Decodable {
        let title: String?
        let content: String
    }

    func execute(arguments: Data) async throws -> String {
        let args: Args
        do {
            args = try JSONDecoder().decode(Args.self, from: arguments)
        } catch {
            let raw = String(data: arguments, encoding: .utf8) ?? "<binary>"
            throw ToolError.invalidArguments(
                reason: "expected {title?: string, content: string}, got: \(raw)"
            )
        }
        let content = args.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw ToolError.invalidArguments(reason: "content ne peut pas être vide")
        }

        let title = args.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false) ? title! : Self.deriveTitle(from: content)
        let memory = store.add(title: resolvedTitle, content: content)
        return "Mémorisé : « \(memory.title) » (id \(memory.id.uuidString))."
    }

    /// Falls back to the first words of the content when no title is given.
    private static func deriveTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n").first.map(String.init) ?? content
        return String(firstLine.prefix(40))
    }
}
