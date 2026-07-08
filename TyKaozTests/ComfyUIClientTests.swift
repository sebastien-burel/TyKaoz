import Foundation
import Testing
@testable import TyKaoz

@Suite(.serialized) @MainActor
struct ComfyUIClientTests {

    // A minimal ComfyUI API-format workflow: one text node with the marker,
    // one seed node.
    private let workflow = """
    {
      "3": {"class_type": "CLIPTextEncode", "inputs": {"text": "%prompt%"}},
      "6": {"class_type": "RandomNoise", "inputs": {"noise_seed": 42}}
    }
    """

    // MARK: - prepareWorkflow

    @Test
    func injectsPromptAndRandomisesSeed() throws {
        let graph = try ComfyUIClient.prepareWorkflow(json: workflow, prompt: "un chat", seed: 999)
        let node3 = graph["3"] as? [String: Any]
        let inputs3 = node3?["inputs"] as? [String: Any]
        #expect(inputs3?["text"] as? String == "un chat")

        let node6 = graph["6"] as? [String: Any]
        let inputs6 = node6?["inputs"] as? [String: Any]
        #expect((inputs6?["noise_seed"] as? NSNumber)?.intValue == 999)
    }

    @Test
    func promptWithSpecialCharsSurvivesReserialization() throws {
        // Quotes / newlines must not corrupt the JSON — JSONSerialization
        // handles the escaping on the way out.
        let tricky = "Say \"hi\"\nline2 \\ end"
        let graph = try ComfyUIClient.prepareWorkflow(json: workflow, prompt: tricky, seed: 1)
        let data = try JSONSerialization.data(withJSONObject: graph)
        let round = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = ((round?["3"] as? [String: Any])?["inputs"] as? [String: Any])?["text"] as? String
        #expect(text == tricky)
    }

    @Test
    func throwsWhenPromptPlaceholderMissing() {
        let noMarker = #"{"3":{"class_type":"CLIPTextEncode","inputs":{"text":"fixed"}}}"#
        #expect(throws: ComfyUIError.missingPromptPlaceholder) {
            _ = try ComfyUIClient.prepareWorkflow(json: noMarker, prompt: "x", seed: 1)
        }
    }

    @Test
    func throwsOnMalformedWorkflow() {
        #expect(throws: ComfyUIError.self) {
            _ = try ComfyUIClient.prepareWorkflow(json: "%prompt% not json", prompt: "x", seed: 1)
        }
    }

    // MARK: - Parameters

    private let paramWorkflow = """
    {
      "3":  {"class_type": "CLIPTextEncode", "inputs": {"text": "%prompt%"}},
      "16": {"class_type": "FluxGuidance", "inputs": {"guidance": "%guidance=2.5%"}},
      "12": {"class_type": "Flux2Scheduler", "inputs": {"steps": "%steps=30%", "sampler": "%sampler=euler%"}},
      "6":  {"class_type": "RandomNoise", "inputs": {"noise_seed": "%seed%"}}
    }
    """

    @Test
    func discoversParametersExcludingPrompt() {
        let params = ComfyUIClient.discoverParameters(in: paramWorkflow)
        let names = params.map(\.name)
        #expect(names.contains("guidance"))
        #expect(names.contains("steps"))
        #expect(names.contains("sampler"))
        #expect(names.contains("seed"))
        #expect(!names.contains("prompt"))
        #expect(params.first { $0.name == "guidance" }?.default == "2.5")
        #expect(params.first { $0.name == "seed" }?.default == "")
    }

    @Test
    func deduplicatesRepeatedMarkers() {
        let json = #"{"a":{"inputs":{"t":"%prompt%","w":"%size=1%","h":"%size=1%"}}}"#
        #expect(ComfyUIClient.discoverParameters(in: json).map(\.name) == ["size"])
    }

    @Test
    func appliesDefaultsOverridesAndCoercion() throws {
        let graph = try ComfyUIClient.prepareWorkflow(
            json: paramWorkflow,
            prompt: "un chat",
            params: ["steps": "40"],   // override; guidance falls back to default
            seed: 123
        )
        func inputs(_ node: String) -> [String: Any]? {
            (graph[node] as? [String: Any])?["inputs"] as? [String: Any]
        }
        #expect(inputs("3")?["text"] as? String == "un chat")
        // guidance default "2.5" → JSON number (Double)
        #expect((inputs("16")?["guidance"] as? NSNumber)?.doubleValue == 2.5)
        // steps overridden "40" → Int
        #expect((inputs("12")?["steps"] as? NSNumber)?.intValue == 40)
        // non-numeric stays a string
        #expect(inputs("12")?["sampler"] as? String == "euler")
        // %seed% marker resolves to the provided seed
        #expect((inputs("6")?["noise_seed"] as? NSNumber)?.intValue == 123)
    }

    // MARK: - parseSubmitResponse

    @Test
    func parsesPromptID() throws {
        let data = Data(#"{"prompt_id":"abc-123","number":1,"node_errors":{}}"#.utf8)
        #expect(try ComfyUIClient.parseSubmitResponse(data) == "abc-123")
    }

    @Test
    func surfacesNodeErrorsAsValidation() {
        let data = Data(#"{"error":"invalid prompt","node_errors":{"3":{"errors":["bad"]}}}"#.utf8)
        #expect(throws: ComfyUIError.self) {
            _ = try ComfyUIClient.parseSubmitResponse(data)
        }
    }

    @Test
    func throwsWhenPromptIDMissing() {
        let data = Data(#"{"number":1}"#.utf8)
        #expect(throws: ComfyUIError.self) {
            _ = try ComfyUIClient.parseSubmitResponse(data)
        }
    }

    // MARK: - parseHistoryImage

    @Test
    func extractsImageFromCompletedHistory() {
        let json = """
        {"pid-1":{"status":{"completed":true},"outputs":{
          "17":{"images":[{"filename":"Flux2_00001_.png","subfolder":"","type":"output"}]}
        }}}
        """
        let ref = ComfyUIClient.parseHistoryImage(Data(json.utf8), promptID: "pid-1")
        #expect(ref?.filename == "Flux2_00001_.png")
        #expect(ref?.type == "output")
        #expect(ref?.subfolder == "")
    }

    @Test
    func returnsNilWhileStillRunning() {
        // Empty history — job not finished yet.
        #expect(ComfyUIClient.parseHistoryImage(Data("{}".utf8), promptID: "pid-1") == nil)
        // Present but no outputs yet.
        let noOutputs = Data(#"{"pid-1":{"status":{"completed":false}}}"#.utf8)
        #expect(ComfyUIClient.parseHistoryImage(noOutputs, promptID: "pid-1") == nil)
    }

    // MARK: - mime type

    @Test
    func infersMimeFromExtension() {
        #expect(ComfyUIClient.mimeType(forFilename: "a.png") == "image/png")
        #expect(ComfyUIClient.mimeType(forFilename: "a.JPG") == "image/jpeg")
        #expect(ComfyUIClient.mimeType(forFilename: "a.jpeg") == "image/jpeg")
        #expect(ComfyUIClient.mimeType(forFilename: "a.webp") == "image/webp")
        #expect(ComfyUIClient.mimeType(forFilename: "noext") == "image/png")
    }
}
