import Foundation
import Testing
@testable import TyKaoz

/// Verifies each cloud client encodes a user message's image attachments
/// into its provider-specific multimodal wire format, and leaves text-only
/// messages untouched.
@Suite
struct CloudVLMEncodingTests {
    private func tempImage() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: url)  // JPEG magic bytes
        return url
    }

    @Test
    func openAIEncodesImagePart() throws {
        let url = try tempImage()
        defer { try? FileManager.default.removeItem(at: url) }

        let dicts = try OpenAICompatibleClient.messagesToDicts(
            [ChatMessage(role: .user, content: "regarde", imageURLs: [url])])
        let content = try #require(dicts.first?["content"] as? [[String: Any]])
        #expect(content.contains { ($0["type"] as? String) == "text" })
        let image = try #require(content.first { ($0["type"] as? String) == "image_url" })
        let imageURL = try #require(image["image_url"] as? [String: Any])
        #expect((imageURL["url"] as? String)?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    @Test
    func anthropicEncodesImageBlock() throws {
        let url = try tempImage()
        defer { try? FileManager.default.removeItem(at: url) }

        let dicts = try AnthropicClient.messagesToDicts(
            [ChatMessage(role: .user, content: "regarde", imageURLs: [url])])
        let content = try #require(dicts.first?["content"] as? [[String: Any]])
        let image = try #require(content.first { ($0["type"] as? String) == "image" })
        let source = try #require(image["source"] as? [String: Any])
        #expect((source["type"] as? String) == "base64")
        #expect((source["media_type"] as? String) == "image/jpeg")
        #expect((source["data"] as? String)?.isEmpty == false)
    }

    @Test
    func geminiEncodesInlineData() throws {
        let url = try tempImage()
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try GoogleClient.contentsFromHistory(
            [ChatMessage(role: .user, content: "regarde", imageURLs: [url])])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let inline = try #require(parts.first { $0["inlineData"] != nil }?["inlineData"] as? [String: Any])
        #expect((inline["mimeType"] as? String) == "image/jpeg")
        #expect((inline["data"] as? String)?.isEmpty == false)
    }

    @Test
    func openAIEncodesMultipleImages() throws {
        let url1 = try tempImage(), url2 = try tempImage()
        defer { try? FileManager.default.removeItem(at: url1); try? FileManager.default.removeItem(at: url2) }

        let dicts = try OpenAICompatibleClient.messagesToDicts(
            [ChatMessage(role: .user, content: "compare", imageURLs: [url1, url2])])
        let content = try #require(dicts.first?["content"] as? [[String: Any]])
        let images = content.filter { ($0["type"] as? String) == "image_url" }
        #expect(images.count == 2)
    }

    @Test
    func textOnlyKeepsPlainStringContent() throws {
        let dicts = try OpenAICompatibleClient.messagesToDicts(
            [ChatMessage(role: .user, content: "bonjour")])
        #expect((dicts.first?["content"] as? String) == "bonjour")
    }
}
