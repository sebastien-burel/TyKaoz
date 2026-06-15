import Foundation
import Testing
@testable import TyKaoz

/// Covers Gemini image generation: the request opts into the IMAGE
/// modality for image models, and inline image parts in the response are
/// surfaced for persistence as attachments.
@Suite
struct GoogleImageGenTests {
    @Test
    func parsesInlineImagePart() throws {
        let line = #"data: {"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"QUJD"}}]}}]}"#
        let info = try GoogleClient.parseLine(Data(line.utf8))
        #expect(info.images.count == 1)
        #expect(info.images.first?.mimeType == "image/png")
        #expect(info.images.first?.base64 == "QUJD")
    }

    @Test
    func imageModelRequestsImageModality() throws {
        let body = try GoogleClient.buildBody(
            model: "gemini-2.5-flash-image",
            messages: [ChatMessage(role: .user, content: "dessine un chat")],
            tools: [])
        let dict = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let gen = try #require(dict["generationConfig"] as? [String: Any])
        let modalities = try #require(gen["responseModalities"] as? [String])
        #expect(modalities.contains("IMAGE"))
    }

    @Test
    func textModelOmitsImageModality() throws {
        let body = try GoogleClient.buildBody(
            model: "gemini-2.5-pro",
            messages: [ChatMessage(role: .user, content: "bonjour")],
            tools: [])
        let dict = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(dict["generationConfig"] == nil)
    }
}
