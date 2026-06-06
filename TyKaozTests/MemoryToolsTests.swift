import Foundation
import Testing
@testable import TyKaoz

@Suite @MainActor
struct MemoryToolsTests {

    private func freshStore() -> MemoryStore {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString)/memories.json")
        return MemoryStore(fileURL: url)
    }

    private func args(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    @Test
    func saveStoresMemory() async throws {
        let store = freshStore()
        let tool = SaveMemoryTool(store: store)
        _ = try await tool.execute(arguments: args(["title": "Prénom", "content": "Sébastien"]))
        #expect(store.memories.count == 1)
        #expect(store.memories.first?.title == "Prénom")
    }

    @Test
    func saveDerivesTitleWhenMissing() async throws {
        let store = freshStore()
        let tool = SaveMemoryTool(store: store)
        _ = try await tool.execute(arguments: args(["content": "Préfère les réponses courtes."]))
        #expect(store.memories.first?.title.isEmpty == false)
    }

    @Test
    func saveRejectsEmptyContent() async {
        let store = freshStore()
        let tool = SaveMemoryTool(store: store)
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: self.args(["content": "   "]))
        }
    }

    @Test
    func listReturnsTitles() async throws {
        let store = freshStore()
        store.add(title: "Langue", content: "français")
        let output = try await ListMemoriesTool(store: store).execute(arguments: args([:]))
        #expect(output.contains("Langue"))
    }

    @Test
    func readByIdReturnsContent() async throws {
        let store = freshStore()
        let m = store.add(title: "Ville", content: "Rennes")
        let output = try await ReadMemoryTool(store: store)
            .execute(arguments: args(["id": m.id.uuidString]))
        #expect(output.contains("Rennes"))
    }

    @Test
    func readWithoutIdReturnsAll() async throws {
        let store = freshStore()
        store.add(title: "A", content: "un")
        store.add(title: "B", content: "deux")
        let output = try await ReadMemoryTool(store: store).execute(arguments: args([:]))
        #expect(output.contains("un"))
        #expect(output.contains("deux"))
    }
}
