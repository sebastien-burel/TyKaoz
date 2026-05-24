import SwiftUI

struct ChatView: View {
    @Binding var conversation: Conversation?
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if let conversation {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(conversation.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: conversation.messages.count) { _, _ in
                        if let last = conversation.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider().background(Brand.Colors.slate)

                inputBar
            } else {
                emptyState
            }
        }
        .background(Brand.Colors.paper)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Écrire un message…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Brand.Fonts.body(14))
                .padding(10)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Brand.Colors.slate.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Brand.Colors.ink)
                .lineLimit(1...6)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Brand.Colors.tide)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(Brand.Colors.paper)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(Brand.Colors.tide.opacity(0.6))
            Text("Sélectionnez une conversation")
                .font(Brand.Fonts.body(14))
                .foregroundStyle(Brand.Colors.slate.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Colors.paper)
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, conversation != nil else { return }
        conversation?.messages.append(Message(role: .user, content: trimmed))
        draft = ""
    }
}

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content)
                .font(Brand.Fonts.body(14))
                .foregroundStyle(textColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var background: some ShapeStyle {
        switch message.role {
        case .user:      return AnyShapeStyle(Brand.Colors.slate)
        case .assistant: return AnyShapeStyle(Color.white)
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user:      return Brand.Colors.paper
        case .assistant: return Brand.Colors.ink
        }
    }

    private var borderColor: Color {
        switch message.role {
        case .user:      return .clear
        case .assistant: return Brand.Colors.slate.opacity(0.15)
        }
    }
}
