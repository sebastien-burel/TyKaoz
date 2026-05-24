import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConversationStore.self) private var store

    @State private var selection: Conversation.ID?

    var body: some View {
        NavigationSplitView {
            ConversationsListView(selection: $selection)
                .navigationTitle("TyKaoz")
        } detail: {
            ChatView(
                conversation: selectedBinding,
                serverURL: settings.serverURL,
                model: settings.selectedModel
            )
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
