import Foundation

protocol LLMProvider: Sendable {
    var id: String { get }
    var displayName: String { get }

    func availability() async -> ProviderAvailability

    /// Streams one round of a chat completion. Pass `tools` to advertise the
    /// callable functions to the model — providers that don't support tool
    /// calling can ignore them. The returned stream emits `.textDelta` for
    /// each chunk of generated text and `.toolCall` whenever the model
    /// finalises a tool invocation (id, name, arguments JSON).
    func chat(
        messages: [ChatMessage],
        tools: [ToolSpec]
    ) -> AsyncThrowingStream<StreamEvent, Error>
}

enum ProviderAvailability: Equatable {
    case ready
    case unavailable(reason: String)
}

/// Events the streaming chat can produce. Text and tool calls are
/// interleaved according to what the model emits. Each `.toolCall` is
/// atomic — providers buffer the arguments internally and emit only when
/// fully assembled, so callers don't have to parse partial JSON.
enum StreamEvent: Sendable, Hashable {
    case textDelta(String)
    case toolCall(id: String, name: String, argumentsJSON: String)
}

struct ChatMessage: Hashable, Sendable {
    enum Role: String, Hashable, Sendable {
        case system
        case user
        case assistant
        case toolCall
        case toolResult
    }

    let role: Role
    let content: String
    let toolCallID: String?
    let toolName: String?
    let toolIsError: Bool?

    init(
        role: Role,
        content: String,
        toolCallID: String? = nil,
        toolName: String? = nil,
        toolIsError: Bool? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.toolIsError = toolIsError
    }
}

/// Wraps a legacy text-only `AsyncThrowingStream<String, Error>` into the
/// new event stream by emitting each delta as `.textDelta`. Used by all
/// providers until tool emission is wired per-provider in Bloc 4.
func wrapAsTextStream(_ source: AsyncThrowingStream<String, Error>) -> AsyncThrowingStream<StreamEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for try await delta in source {
                    if Task.isCancelled { break }
                    continuation.yield(.textDelta(delta))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Drops tool-related entries from the history when targeting a provider
/// that doesn't yet know how to serialise them. Temporary helper for Bloc 3;
/// Bloc 4 replaces each provider's mapping with proper tool round-trip.
func dropToolMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
    messages.filter { $0.role == .user || $0.role == .assistant || $0.role == .system }
}

extension ChatMessage {
    /// Maps a stored Message to a ChatMessage. Always succeeds — tool roles
    /// carry their metadata through so providers can serialise them into
    /// their own wire formats in Bloc 4.
    init(_ message: Message) {
        let role: Role
        switch message.role {
        case .user:       role = .user
        case .assistant:  role = .assistant
        case .toolCall:   role = .toolCall
        case .toolResult: role = .toolResult
        }
        self.init(
            role: role,
            content: message.content,
            toolCallID: message.toolCallID,
            toolName: message.toolName,
            toolIsError: message.toolIsError
        )
    }
}
