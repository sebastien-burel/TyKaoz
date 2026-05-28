import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConversationStore.self) private var store
    @Environment(FileSpaceStore.self) private var fileSpaces

    @State private var selection: Conversation.ID?

    /// Built fresh each render so newly-authorised folders flow into the file
    /// tools without restarting. Bloc 6 will make individual tools toggleable.
    private var toolRegistry: ToolRegistry {
        let roots = fileSpaces.authorizedRoots
        return ToolRegistry(tools: [
            CurrentDateTimeTool(),
            FetchURLTool(),
            ListDirectoryTool(roots: roots),
            ReadFileTool(roots: roots),
            GrepFilesTool(roots: roots)
        ])
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
