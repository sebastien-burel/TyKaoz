import Foundation
import Testing
@testable import TySkaoz

@Suite
struct LocalOpenAIProviderTests {

    @Test
    func normalizeAppendsV1WhenMissing() {
        let raw = URL(string: "http://localhost:8000")!
        let out = LocalOpenAIProvider.normalize(raw)
        #expect(out.absoluteString == "http://localhost:8000/v1")
    }

    @Test
    func normalizeKeepsExistingV1Prefix() {
        let raw = URL(string: "http://localhost:8000/v1")!
        let out = LocalOpenAIProvider.normalize(raw)
        #expect(out.absoluteString == "http://localhost:8000/v1")
    }

    @Test
    func normalizeKeepsExistingV1Slash() {
        let raw = URL(string: "http://localhost:8000/v1/")!
        let out = LocalOpenAIProvider.normalize(raw)
        #expect(out.absoluteString == "http://localhost:8000/v1/")
    }

    @Test
    func normalizeKeepsOtherVersions() {
        // Some proxies serve /v4 (z.ai-like). We leave it alone.
        let raw = URL(string: "https://gateway.example.com/v4")!
        let out = LocalOpenAIProvider.normalize(raw)
        #expect(out.absoluteString == "https://gateway.example.com/v4")
    }
}
