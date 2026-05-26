import Foundation
import Testing
@testable import TySkaoz

@Suite(.serialized) @MainActor
struct FetchURLToolTests {

    @Test
    func rejectsMalformedJSON() async {
        let tool = FetchURLTool()
        do {
            _ = try await tool.execute(arguments: Data("not-json".utf8))
            Issue.record("expected ToolError")
        } catch let error as ToolError {
            if case .invalidArguments = error {
                // ok
            } else {
                Issue.record("wrong ToolError case: \(error)")
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test
    func rejectsNonHTTPScheme() async {
        let tool = FetchURLTool()
        let args = Data(#"{"url":"file:///etc/passwd"}"#.utf8)
        do {
            _ = try await tool.execute(arguments: args)
            Issue.record("expected ToolError")
        } catch let error as ToolError {
            if case .invalidArguments(let reason) = error {
                #expect(reason.contains("http"))
            } else {
                Issue.record("wrong ToolError case: \(error)")
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test
    func returnsPlainTextBodyAsIs() async throws {
        let body = "Bonjour TyKaoz."
        let session = MockURLProtocol.session(data: Data(body.utf8), status: 200)
        let tool = FetchURLTool(session: session)

        let result = try await tool.execute(arguments: Data(#"{"url":"http://example.com"}"#.utf8))
        #expect(result.contains("Bonjour TyKaoz."))
    }

    @Test
    func truncatesAtMaxChars() async throws {
        let body = String(repeating: "a", count: 5000)
        let session = MockURLProtocol.session(data: Data(body.utf8), status: 200)
        let tool = FetchURLTool(session: session)

        let result = try await tool.execute(
            arguments: Data(#"{"url":"http://example.com","max_chars":1000}"#.utf8)
        )
        #expect(result.hasSuffix("[truncated]"))
        // 1000 chars + "\n[truncated]"
        #expect(result.count == 1000 + "\n[truncated]".count)
    }

    @Test
    func surfacesHTTPErrorAsToolError() async {
        let session = MockURLProtocol.session(data: Data(), status: 500)
        let tool = FetchURLTool(session: session)

        do {
            _ = try await tool.execute(arguments: Data(#"{"url":"http://example.com"}"#.utf8))
            Issue.record("expected ToolError")
        } catch let error as ToolError {
            if case .execution(let message) = error {
                #expect(message.contains("500"))
            } else {
                Issue.record("wrong ToolError case: \(error)")
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    // MARK: - HTML stripping (pure)

    @Test
    func stripsBasicTags() {
        let html = "<p>Hello <b>world</b></p>"
        #expect(FetchURLTool.stripHTML(html) == "Hello world")
    }

    @Test
    func stripsScriptAndStyleBlocks() {
        let html = """
        <html><head><style>body{color:red}</style></head>
        <body><script>alert(1);</script><p>Hi</p></body></html>
        """
        let result = FetchURLTool.stripHTML(html)
        #expect(!result.contains("alert"))
        #expect(!result.contains("color:red"))
        #expect(result.contains("Hi"))
    }

    @Test
    func decodesCommonEntities() {
        let html = "<p>tom &amp; jerry &lt; salut &gt; &quot;ok&quot; &#39;test&#39;</p>"
        let result = FetchURLTool.stripHTML(html)
        #expect(result.contains("tom & jerry"))
        #expect(result.contains("< salut >"))
        #expect(result.contains("\"ok\""))
        #expect(result.contains("'test'"))
    }
}
