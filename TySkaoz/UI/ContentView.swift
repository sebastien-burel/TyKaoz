import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConversationStore.self) private var store
    @Environment(FileSpaceStore.self) private var fileSpaces
    @Environment(MemoryStore.self) private var memory
    @Environment(PluginStore.self) private var plugins

    @State private var selection: Conversation.ID?

    /// Built fresh each render so newly-authorised folders, tool toggles and
    /// installed plugins flow into the live registry without restarting.
    ///
    /// Apple Intelligence uses a separate, opt-in tool set because the
    /// on-device model's tiny context window fills up fast with tool schemas.
    /// Everywhere else the global on/off applies.
    private var toolRegistry: ToolRegistry {
        let isApple = settings.selectedProviderID == "apple"
        let isEnabled: (String) -> Bool = { name in
            isApple ? settings.isAppleToolEnabled(name) : settings.isToolEnabled(name)
        }

        let builtins = ToolCatalog.allTools(
            roots: fileSpaces.authorizedRoots,
            memory: memory,
            braveAPIKey: settings.braveAPIKey
        ).filter { isEnabled($0.spec.name) }

        let pluginTools = plugins.tools()
            .filter { isEnabled($0.spec.name) }

        return ToolRegistry(tools: builtins + pluginTools)
    }

    var body: some View {
        let tools = toolRegistry
        return NavigationSplitView {
            ConversationsListView(selection: $selection)
                .navigationTitle("TyKaoz")
        } detail: {
            ChatView(
                conversation: selectedBinding,
                provider: ProviderFactory.make(from: settings, tools: tools),
                providerID: settings.selectedProviderID,
                tools: tools
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ChatModelPicker()
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var selectedBinding: Binding<Conversation?> {
        Binding(
            get: { store.conversations.first(where: { $0.id == selection }) },
            set: { newValue in
                guard let newValue else { return }
                store.update(newValue)
            }
        )
    }
}
