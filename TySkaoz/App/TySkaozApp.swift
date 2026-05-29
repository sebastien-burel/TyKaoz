import SwiftUI

@main
struct TySkaozApp: App {
    @State private var settings = AppSettings()
    @State private var conversationStore = ConversationStore()
    @State private var fileSpaceStore = FileSpaceStore()
    @State private var memoryStore = MemoryStore()

    init() {
        FontRegistration.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(conversationStore)
                .environment(fileSpaceStore)
                .environment(memoryStore)
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }

        Settings {
            SettingsPanelView()
                .environment(settings)
                .environment(fileSpaceStore)
                .environment(memoryStore)
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }
    }
}
