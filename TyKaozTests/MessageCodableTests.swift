import Foundation
import Testing
@testable import TyKaoz

struct MessageCodableTests {

    // MARK: - Backward compatibility

    @Test
    func decodesLegacyMessageWithoutToolFields() throws {
        // Old conversation files only carry id/role/content/timestamp.
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "role": "user",
          "content": "Bonjour",
          "timestamp": "2026-05-25T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(Message.self, from: json)

        #expect(message.role == .user)
        #expect(message.content == "Bonjour")
        #expect(message.toolCallID == nil)
        #expect(message.toolName == nil)
        #expect(message.toolIsError == nil)
    }

    @Test
    func decodesLegacyConversationFile() throws {
        // Real-world snapshot mirroring what ConversationStore wrote in
        // Phase 4: a Conversation with two simple messages and no tool data.
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "Salut",
          "createdAt": "2026-05-25T12:00:00Z",
          "messages": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "role": "user",
              "content": "Salut",
              "timestamp": "2026-05-25T12:00:00Z"
            },
            {
              "id": "33333333-3333-3333-3333-333333333333",
              "role": "assistant",
              "content": "Salut !",
              "timestamp": "2026-05-25T12:00:01Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let conv = try decoder.decode(Conversation.self, from: json)

        #expect(conv.messages.count == 2)
        #expect(conv.messages.allSatisfy { $0.toolName == nil && $0.toolCallID == nil })
    }

    // MARK: - Round-trip with tool fields

    @Test
    func roundTripsToolCallMessage() throws {
        let original = Message(
            role: .toolCall,
            content: #"{"url":"https://example.com"}"#,
            toolCallID: "call_abc",
            toolName: "fetch_url"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Message.self, from: data)

        #expect(decoded.role == .toolCall)
        #expect(decoded.toolCallID == "call_abc")
        #expect(decoded.toolName == "fetch_url")
        #expect(decoded.content == #"{"url":"https://example.com"}"#)
        #expect(decoded.toolIsError == nil)
    }

    @Test
    func roundTripsToolResultMessage() throws {
        let original = Message(
            role: .toolResult,
            content: "Bonjour TyKaoz.",
            toolCallID: "call_abc",
            toolIsError: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Message.self, from: data)

        #expect(decoded.role == .toolResult)
        #expect(decoded.toolCallID == "call_abc")
        #expect(decoded.toolIsError == false)
        #expect(decoded.toolName == nil)
    }
}
