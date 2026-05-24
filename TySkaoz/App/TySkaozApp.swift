import SwiftUI

@main
struct TySkaozApp: App {
    @State private var settings = AppSettings()
    @State private var conversationStore = ConversationStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(conversationStore)
        }

        Settings {
            SettingsPanelView()
                .environment(settings)
        }
    }
}
