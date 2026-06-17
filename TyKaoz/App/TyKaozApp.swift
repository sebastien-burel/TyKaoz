import SwiftUI

@main
struct TyKaozApp: App {
    /// Identifier the menu's "Nouvelle fenêtre" command uses with
    /// `openWindow(id:)` to spawn a new main window.
    static let mainWindowID = "main"

    /// Wiki browser window — opened via Cmd-Shift-K or the View menu.
    static let wikiWindowID = "wiki"

    /// Agents window — opened via Cmd-Shift-A or the Window menu.
    static let agentsWindowID = "agents"

    /// Settings window — opened via Cmd-, (see AppCommands). A regular
    /// `Window` rather than the `Settings` scene so it stays resizable and
    /// free of the preferences-window margins.
    static let settingsWindowID = "settings"

    @Environment(\.scenePhase) private var scenePhase

    @State private var settings = AppSettings()
    @State private var conversationStore = ConversationStore()
    @State private var fileSpaceStore = FileSpaceStore()
    @State private var memoryStore = MemoryStore()
    @State private var pluginStore = PluginStore()
    @State private var agentStore = AgentStore()
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
                .environment(agentStore)
                .environment(wikiManager)
                .environment(mlxDownloads)
                .environment(ModelCatalogService.shared)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .task {
                    // Pull the live model manifest; failure is silent,
                    // the cache/bundle catalog keeps serving.
                    await ModelCatalogService.shared.refresh()
                }
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
                // Flush debounced conversation saves when the app loses
                // focus, backgrounds, or quits — otherwise a save still in
                // its 300 ms window is lost if the process is killed (e.g.
                // an Xcode re-run), dropping the last message / attachment.
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        Task { await conversationStore.flushPendingSaves() }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willResignActiveNotification)) { _ in
                    Task { await conversationStore.flushPendingSaves() }
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification)) { _ in
                    Task { await conversationStore.flushPendingSaves() }
                }
        }
        .commands {
            AppCommands()
        }

        Window("Réglages", id: Self.settingsWindowID) {
            SettingsPanelView()
                .environment(settings)
                .environment(fileSpaceStore)
                .environment(memoryStore)
                .environment(pluginStore)
                .environment(wikiManager)
                .environment(mlxDownloads)
                .environment(ModelCatalogService.shared)
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }
        .defaultSize(width: 860, height: 600)
        .windowResizability(.contentMinSize)

        WindowGroup(id: Self.wikiWindowID) {
            WikiBrowserView()
                .environment(settings)
                .environment(wikiManager)
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }
        .defaultSize(width: 900, height: 600)

        WindowGroup(id: Self.agentsWindowID) {
            AgentsView()
                .environment(settings)
                .environment(agentStore)
                .environment(fileSpaceStore)
                .environment(memoryStore)
                .environment(pluginStore)
                .environment(wikiManager)
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }
        .defaultSize(width: 860, height: 640)
    }
}
