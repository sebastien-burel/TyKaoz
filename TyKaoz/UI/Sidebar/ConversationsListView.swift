import SwiftUI

struct ConversationsListView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Binding var selection: Conversation.ID?

    @State private var editingID: Conversation.ID?
    @State private var editedTitle: String = ""
    @FocusState private var titleFocused: Bool
    @FocusState private var listFocused: Bool

    @State private var deletionTarget: Conversation?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.conversations) { conversation in
                        rowContainer(for: conversation)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            Divider()

            HStack {
                Button {
                    openWindow(id: TyKaozApp.settingsWindowID)
                } label: {
                    Label("Réglages", systemImage: "gearshape")
                        .font(Brand.Fonts.body(12))
                        .foregroundStyle(Brand.Colors.slate)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Brand.Colors.paper)
        .frame(minWidth: 220)
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .focusedSceneValue(\.newConversationAction, createConversation)
        .toolbar {
            ToolbarItem {
                Button(action: createConversation) {
                    Label("Nouvelle conversation", systemImage: "plus")
                }
            }
        }
        .onDeleteCommand {
            guard let id = selection,
                  let conv = store.conversations.first(where: { $0.id == id })
            else { return }
            deletionTarget = conv
        }
        .confirmationDialog(
            "Supprimer la conversation ?",
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            presenting: deletionTarget
        ) { conv in
            Button("Supprimer", role: .destructive) {
                if selection == conv.id { selection = nil }
                store.delete(id: conv.id)
            }
            Button("Annuler", role: .cancel) {}
        } message: { conv in
            Text("« \(conv.title) » sera supprimée définitivement.")
        }
    }

    private func rowContainer(for conversation: Conversation) -> some View {
        row(for: conversation)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selection == conversation.id ? Brand.Colors.slate.opacity(0.12) : .clear)
            )
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .onTapGesture {
                selection = conversation.id
                listFocused = true
            }
            .contextMenu {
                Button("Renommer") { beginEditing(conversation) }
                Button("Supprimer", role: .destructive) {
                    deletionTarget = conversation
                }
            }
    }

    @ViewBuilder
    private func row(for conversation: Conversation) -> some View {
        if editingID == conversation.id {
            TextField("", text: $editedTitle)
                .font(Brand.Fonts.body(14))
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .onSubmit { commitRename(conversation) }
                .onExitCommand { editingID = nil }
                .onChange(of: titleFocused) { _, focused in
                    if !focused && editingID == conversation.id {
                        commitRename(conversation)
                    }
                }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(Brand.Fonts.body(14))
                    .foregroundStyle(Brand.Colors.ink)
                Text(conversation.createdAt, style: .date)
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(Brand.Colors.slate.opacity(0.6))
            }
        }
    }

    private func createConversation() {
        let new = Conversation(title: ConversationTitler.defaultTitle)
        store.add(new)
        selection = new.id
        listFocused = true
    }

    private func beginEditing(_ conversation: Conversation) {
        editedTitle = conversation.title
        editingID = conversation.id
        // Focus on the next runloop tick so the TextField has appeared.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            titleFocused = true
        }
    }

    private func commitRename(_ conversation: Conversation) {
        store.rename(id: conversation.id, to: editedTitle)
        editingID = nil
    }
}
