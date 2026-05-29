import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConversationStore.self) private var store
    @Environment(FileSpaceStore.self) private var fileSpaces
    @Environment(MemoryStore.self) private var memory

    @State private var selection: Conversation.ID?

    /// Built fresh each render so newly-authorised folders and tool toggles
    /// flow into the live registry without restarting.
    private var toolRegistry: ToolRegistry {
        ToolRegistry(tools: ToolCatalog.enabledTools(
            roots: fileSpaces.authorizedRoots,
            memory: memory,
            settings: settings
        ))
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
