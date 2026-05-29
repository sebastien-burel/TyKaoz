import Foundation
import Testing
@testable import TySkaoz

@Suite @MainActor
struct MemoryStoreTests {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString)/memories.json")
    }

    @Test
    func addPersistsAcrossReload() {
        let url = tempFile()
        let store = MemoryStore(fileURL: url)
        store.add(title: "Prénom", content: "L'utilisateur s'appelle Sébastien.")

        let reloaded = MemoryStore(fileURL: url)
        #expect(reloaded.memories.count == 1)
        #expect(reloaded.memories.first?.title == "Prénom")
    }

    @Test
    func deleteRemovesMemory() {
        let store = MemoryStore(fileURL: tempFile())
        let m = store.add(title: "Temp", content: "à oublier")
        store.delete(id: m.id)
        #expect(store.memories.isEmpty)
    }

    @Test
    func promptContextNilWhenEmpty() {
        let store = MemoryStore(fileURL: tempFile())
        #expect(store.promptContext == nil)
    }

    @Test
    func promptContextListsMemories() {
        let store = MemoryStore(fileURL: tempFile())
        store.add(title: "Langue", content: "Préfère le français.")
        let context = store.promptContext
        #expect(context?.contains("Langue") == true)
        #expect(context?.contains("Préfère le français.") == true)
    }
}
