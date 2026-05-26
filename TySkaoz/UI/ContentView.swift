import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConversationStore.self) private var store

    @State private var selection: Conversation.ID?

    /// Minimal default tool set wired up so the OpenAI-compatible providers
    /// can exercise the loop end-to-end. Bloc 6 will replace this with a
    /// curated, user-toggleable registry.
    private let toolRegistry = ToolRegistry(tools: [
        CurrentDateTimeTool(),
        FetchURLTool()
    ])

    var body: some View {
        NavigationSplitView {
            ConversationsListView(selection: $selection)
                .navigationTitle("TyKaoz")
        } detail: {
            ChatView(
                conversation: selectedBinding,
                provider: ProviderFactory.make(from: settings),
                providerID: settings.selectedProviderID,
                tools: toolRegistry
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
