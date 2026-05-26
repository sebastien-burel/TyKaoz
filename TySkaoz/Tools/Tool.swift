import Foundation

/// Describes a tool: the metadata an LLM needs to decide to call it, and how
/// the app exposes the schema in its API requests. `inputSchemaJSON` is kept
/// as raw JSON text so each provider can splice it verbatim into its tool
/// definition payload — providers disagree about minor schema conventions,
/// passing through avoids re-encoding bugs.
struct ToolSpec: Hashable, Sendable {
    let name: String
    let description: String
    let inputSchemaJSON: String
}

/// One invocation produced by the LLM. The id is provider-assigned and used
/// to correlate the result back to the same call in multi-turn / parallel
/// tool use. `arguments` is the raw JSON body the LLM emitted — each tool
/// decodes into its own typed argument struct.
struct ToolCall: Hashable, Sendable {
    let id: String
    let toolName: String
    let arguments: Data
}

/// The serialised result of a tool execution. Always a string because every
/// provider's tool-result protocol consumes strings. If a tool wants to
/// return structured data, it serialises to JSON itself.
struct ToolResult: Hashable, Sendable {
    let callID: String
    let content: String
    let isError: Bool
}

enum ToolError: Error, LocalizedError, Equatable {
    case invalidArguments(reason: String)
    case execution(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let reason): return "Arguments invalides : \(reason)"
        case .execution(let message):       return message
        }
    }
}

protocol Tool: Sendable {
    var spec: ToolSpec { get }
    func execute(arguments: Data) async throws -> String
}
