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

    // MARK: - Secret placeholders

    @Test
    func detectsSecretPlaceholdersInHeaders() throws {
        let json = #"""
        {"name":"p","tools":[{"name":"t","description":"d","input_schema":{"type":"object"},
        "url":"https://x.io","headers":{"X-Token":"***APIKEY***","Accept":"application/json"}}]}
        """#
        let manifest = try PluginManifest(data: Data(json.utf8))
        #expect(manifest.tools[0].secretNames == ["APIKEY"])
    }

    @Test
    func detectsSecretPlaceholderInURL() throws {
        let json = #"""
        {"name":"p","tools":[{"name":"t","description":"d","input_schema":{"type":"object"},
        "url":"https://x.io/?key=***TOKEN***"}]}
        """#
        let manifest = try PluginManifest(data: Data(json.utf8))
        #expect(manifest.tools[0].secretNames == ["TOKEN"])
    }

    @Test
    func substitutesKnownPlaceholdersOnly() {
        let text = "Bearer ***A*** and ***B***"
        let result = PluginSecrets.substitute(in: text, secrets: ["A": "secret"])
        #expect(result == "Bearer secret and ***B***")
    }

    @Test
    func substitutesArgumentPlaceholdersInURL() {
        let template = "https://api.example.com/v8/finance/chart/{symbol}"
        let (result, used) = PluginArguments.substitute(
            in: template,
            arguments: ["symbol": "AAPL", "range": "5d"]
        )
        #expect(result == "https://api.example.com/v8/finance/chart/AAPL")
        // Only the path placeholder is consumed; `range` stays for the query.
        #expect(used == ["symbol"])
    }

    @Test
    func integerArgumentDoesNotBridgeToBool() {
        // Regression: JSONSerialization gives NSNumber, and `as? Bool` matches
        // 0/1 NSNumbers — `count: 1` must render as "1", not "true".
        let json = Data(#"{"count":1,"flag":true}"#.utf8)
        let dict = try! JSONSerialization.jsonObject(with: json) as! [String: Any]
        let (result, _) = PluginArguments.substitute(
            in: "https://x.io/{count}/{flag}",
            arguments: dict
        )
        #expect(result == "https://x.io/1/true")
    }

    @Test
    func percentEncodesArgumentValues() {
        let (result, _) = PluginArguments.substitute(
            in: "https://x.io/{q}",
            arguments: ["q": "a b&c"]
        )
        #expect(result == "https://x.io/a%20b&c" || result == "https://x.io/a%20b%26c")
    }
}
