import SwiftUI

@main
struct TyKaozApp: App {
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
    @State private var mlxDownloads = MLXDownloadCenter()

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
                .environment(mlxDownloads)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .onAppear {
                    wikiManager.reconcile(settings: settings)
                    // Launch-time LRU pass. Pinning the currently-
                    // configured wiki embedding model so a stale
                    // cap doesn't evict the live one.
                    let cap = Int64(settings.mlxCacheCapGB * 1024 * 1024 * 1024)
                    let pinned: Set<String> = settings.wikiEmbeddingProviderID == "mlx"
                        ? [settings.wikiEmbeddingModelID]
                        : []
                    _ = MLXModelStore.shared.evictIfOverCap(cap, pinned: pinned)
                }
                .onChange(of: settings.wikiEnabled) { _, _ in
                    wikiManager.reconcile(settings: settings)
                }
                .onChange(of: settings.serverURLString) { _, _ in
                    wikiManager.reconcile(settings: settings)
                }
                .onChange(of: settings.localOpenAIBaseURLString) { _, _ in
                    wikiManager.reconcile(settings: settings)
                }
                .onChange(of: settings.wikiEmbeddingModelID) { _, _ in
                    wikiManager.reconcile(settings: settings)
                }
                .onChange(of: settings.wikiEmbeddingProviderID) { _, _ in
                    wikiManager.reconcile(settings: settings)
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
                .environment(mlxDownloads)
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
