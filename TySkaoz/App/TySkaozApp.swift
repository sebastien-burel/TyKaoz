import SwiftUI

@main
struct TySkaozApp: App {
    @State private var settings = AppSettings()
    @State private var conversationStore = ConversationStore()

    init() {
        FontRegistration.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(conversationStore)
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }

        Settings {
            SettingsPanelView()
                .environment(settings)
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }
    }
}
