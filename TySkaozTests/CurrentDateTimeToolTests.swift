import Foundation
import Testing
@testable import TySkaoz

struct CurrentDateTimeToolTests {

    @Test
    func returnsISO8601String() async throws {
        let tool = CurrentDateTimeTool()
        let output = try await tool.execute(arguments: Data("{}".utf8))

        // Must round-trip through ISO8601DateFormatter
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        #expect(formatter.date(from: output) != nil)
    }

    @Test
    func toleratesAnyJSONArgumentsBecauseSchemaIsEmpty() async throws {
        let tool = CurrentDateTimeTool()
        // Even nonsense args should not throw — the spec advertises no input.
        let output = try await tool.execute(arguments: Data(#"{"unrelated": 42}"#.utf8))
        #expect(!output.isEmpty)
    }
}
