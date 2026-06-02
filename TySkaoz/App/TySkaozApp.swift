import SwiftUI

@main
struct TySkaozApp: App {
    /// Identifier the menu's "Nouvelle fenêtre" command uses with
    /// `openWindow(id:)` to spawn a new main window.
    static let mainWindowID = "main"

    /// Wiki browser window — opened via Cmd-Shift-K or the View menu.
    static let wikiWindowID = "wiki"

    @State private var settings = AppSettings()
    @State private var conversationStore = ConversationStore()
    @State private var fileSpaceStore = FileSpaceStore()
    @State private var memoryStore = MemoryStore()
    @State private var pluginStore = PluginStore()
    @State private var wikiManager = WikiManager()

    init() {
        FontRegistration.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            ContentView()
                .environment(settings)
                .environment(conversationStore)
                .environment(fileSpaceStore)
                .environment(memoryStore)
                .environment(pluginStore)
                .environment(wikiManager)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .onAppear {
                    wikiManager.reconcile(settings: settings, ollamaBaseURL: settings.serverURL)
                }
                .onChange(of: settings.wikiEnabled) { _, _ in
                    wikiManager.reconcile(settings: settings, ollamaBaseURL: settings.serverURL)
                }
                .onChange(of: settings.serverURLString) { _, _ in
                    wikiManager.reconcile(settings: settings, ollamaBaseURL: settings.serverURL)
                }
                .onChange(of: settings.wikiEmbeddingModelID) { _, _ in
                    wikiManager.reconcile(settings: settings, ollamaBaseURL: settings.serverURL)
                }
        }
        .commands {
            AppCommands()
        }

        Settings {
            SettingsPanelView()
                .environment(settings)
                .environment(fileSpaceStore)
                .environment(memoryStore)
                .environment(pluginStore)
                .environment(wikiManager)
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }

        WindowGroup(id: Self.wikiWindowID) {
            WikiBrowserView()
                .environment(settings)
                .environment(wikiManager)
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }
        .defaultSize(width: 900, height: 600)
    }
}
