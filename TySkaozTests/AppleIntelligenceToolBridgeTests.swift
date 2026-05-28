import Foundation
import Testing
@testable import TySkaoz

/// The bridge translates our tools' JSON Schema into Foundation Models'
/// `GenerationSchema`. `GenerationSchema` is opaque, so we assert the
/// translation accepts the JSON Schema subset our tools use without throwing.
@Suite
struct AppleIntelligenceToolBridgeTests {

    @Test
    func translatesEmptyObjectSchema() throws {
        let spec = ToolSpec(
            name: "current_datetime",
            description: "Returns now.",
            inputSchemaJSON: #"{"type":"object","properties":{}}"#
        )
        _ = try AppleIntelligenceProvider.generationSchema(for: spec)
    }

    @Test
    func translatesRequiredOptionalAndEnum() throws {
        let spec = ToolSpec(
            name: "fetch",
            description: "Fetches a URL.",
            inputSchemaJSON: #"""
            {
              "type": "object",
              "properties": {
                "url": {"type": "string", "description": "The URL"},
                "max_chars": {"type": "integer", "description": "Limit"},
                "mode": {"type": "string", "enum": ["text", "html"]}
              },
              "required": ["url"]
            }
            """#
        )
        _ = try AppleIntelligenceProvider.generationSchema(for: spec)
    }

    @Test
    func translatesMalformedSchemaAsEmptyObject() throws {
        // A non-JSON schema string degrades to an empty object rather than
        // throwing, so a misconfigured tool simply exposes no parameters.
        let spec = ToolSpec(
            name: "broken",
            description: "Bad schema.",
            inputSchemaJSON: "not json"
        )
        _ = try AppleIntelligenceProvider.generationSchema(for: spec)
    }
}
