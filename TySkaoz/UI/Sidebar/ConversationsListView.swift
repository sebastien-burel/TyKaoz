import SwiftUI

struct ConversationsListView: View {
    @Binding var conversations: [Conversation]
    @Binding var selection: Conversation.ID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(conversations) { conversation in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(conversation.title)
                            .font(Brand.Fonts.body(14))
                            .foregroundStyle(Brand.Colors.ink)
                        Text(conversation.createdAt, style: .date)
                            .font(Brand.Fonts.body(11))
                            .foregroundStyle(Brand.Colors.slate.opacity(0.6))
                    }
                    .padding(.vertical, 4)
                    .tag(conversation.id)
                }
            }
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                SettingsLink {
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
        .toolbar {
            ToolbarItem {
                Button {
                    let new = Conversation(title: "Nouvelle conversation")
                    conversations.append(new)
                    selection = new.id
                } label: {
                    Label("Nouvelle conversation", systemImage: "plus")
                }
            }
        }
    }
}
