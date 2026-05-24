import SwiftUI

@main
struct TySkaozApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        Settings {
            SettingsPanelView()
        }
    }
}
