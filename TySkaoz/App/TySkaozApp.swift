import SwiftUI

@main
struct TySkaozApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
        }

        Settings {
            SettingsPanelView()
                .environment(settings)
        }
    }
}
