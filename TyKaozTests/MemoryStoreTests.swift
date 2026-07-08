import Foundation
import Testing
@testable import TyKaoz

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

    @Test
    func promptContextIsReframedAsPreferencesNotLongTermMemory() {
        let store = MemoryStore(fileURL: tempFile())
        store.add(title: "Langue", content: "Français.")
        let context = store.promptContext ?? ""
        // The wiki owns "mémoire à long terme"; memory is now "préférences".
        #expect(context.contains("Préférences"))
        #expect(!context.contains("Mémoire à long terme"))
    }

    @Test
    func promptContextStaysWithinCharacterBudget() {
        let store = MemoryStore(fileURL: tempFile())
        // 30 fat entries (~200 chars each) would blow past any sane budget.
        for i in 0..<30 {
            store.add(title: "Note \(i)", content: String(repeating: "x", count: 200))
        }
        let context = store.promptContext ?? ""
        #expect(context.count < 1_200)   // budget 800 + header slack
        // Newest pin survives; the oldest is dropped from injection.
        #expect(context.contains("Note 29"))
        #expect(!context.contains("Note 0 "))
    }
}
