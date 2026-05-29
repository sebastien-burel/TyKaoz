import Foundation
import Testing
@testable import TySkaoz

@Suite
struct PluginManifestTests {

    private let valid = #"""
    {
      "name": "Météo",
      "description": "Plugin météo",
      "tools": [
        {
          "name": "get_weather",
          "description": "Renvoie la météo d'une ville.",
          "input_schema": {"type":"object","properties":{"city":{"type":"string"}},"required":["city"]},
          "url": "https://api.example.com/weather",
          "method": "POST",
          "headers": {"X-Api-Key": "secret"}
        }
      ]
    }
    """#

    @Test
    func parsesValidManifest() throws {
        let manifest = try PluginManifest(data: Data(valid.utf8))
        #expect(manifest.name == "Météo")
        #expect(manifest.tools.count == 1)
        let tool = manifest.tools[0]
        #expect(tool.name == "get_weather")
        #expect(tool.method == .post)
        #expect(tool.headers["X-Api-Key"] == "secret")
        #expect(tool.inputSchemaJSON.contains("city"))
    }

    @Test
    func defaultsMethodToPost() throws {
        let json = #"""
        {"name":"p","tools":[{"name":"t","description":"d","input_schema":{"type":"object"},"url":"https://x.io"}]}
        """#
        let manifest = try PluginManifest(data: Data(json.utf8))
        #expect(manifest.tools[0].method == .post)
    }

    @Test
    func rejectsInvalidJSON() {
        #expect(throws: PluginError.self) {
            _ = try PluginManifest(data: Data("not json".utf8))
        }
    }

    @Test
    func rejectsMissingTools() {
        let json = #"{"name":"p","tools":[]}"#
        #expect(throws: PluginError.noTools) {
            _ = try PluginManifest(data: Data(json.utf8))
        }
    }

    @Test
    func rejectsNonHTTPURL() {
        let json = #"""
        {"name":"p","tools":[{"name":"t","description":"d","input_schema":{"type":"object"},"url":"file:///etc/passwd"}]}
        """#
        #expect(throws: PluginError.self) {
            _ = try PluginManifest(data: Data(json.utf8))
        }
    }
}
