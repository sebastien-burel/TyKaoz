import SwiftUI

struct ContentView: View {
    @State private var conversations: [Conversation] = MockData.conversations
    @State private var selection: Conversation.ID?

    var body: some View {
        NavigationSplitView {
            ConversationsListView(
                conversations: $conversations,
                selection: $selection
            )
            .navigationTitle("TyKaoz")
        } detail: {
            ChatView(conversation: selectedBinding)
        }
        .preferredColorScheme(.light)
    }

    private var selectedBinding: Binding<Conversation?> {
        Binding(
            get: { conversations.first(where: { $0.id == selection }) },
            set: { newValue in
                guard let newValue,
                      let idx = conversations.firstIndex(where: { $0.id == newValue.id })
                else { return }
                conversations[idx] = newValue
            }
        )
    }
}

#Preview {
    ContentView()
}
