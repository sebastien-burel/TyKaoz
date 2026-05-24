import SwiftUI

struct ChatView: View {
    @Binding var conversation: Conversation?
    let serverURL: URL?
    let model: String?

    @State private var session = ChatSession()
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if conversation != nil {
                messagesScroll

                if case let .failed(message) = session.state {
                    failureBanner(message)
                }

                Divider().background(Brand.Colors.slate.opacity(0.15))
                inputBar
            } else {
                emptyState
            }
        }
        .background(Brand.Colors.paper)
    }

    @ViewBuilder
    private var messagesScroll: some View {
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
                .onChange(of: conversation.messages.last?.content) { _, _ in
                    if let last = conversation.messages.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $draft, axis: .vertical)
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
                .disabled(!canType)
                .onSubmit(send)

            actionButton
        }
        .padding(12)
        .background(Brand.Colors.paper)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch session.state {
        case .streaming:
            Button(action: { session.stop() }) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Brand.Colors.ember)
            }
            .buttonStyle(.plain)
            .help("Arrêter la génération")
        default:
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(canSend ? Brand.Colors.tide : Brand.Colors.slate.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
    }

    private func failureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(Brand.Colors.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
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

    private var placeholder: String {
        if serverURL == nil { return "Configurez le serveur Ollama dans les réglages…" }
        if model == nil { return "Sélectionnez un modèle dans les réglages…" }
        return "Écrire un message…"
    }

    private var canType: Bool {
        serverURL != nil && model != nil && conversation != nil && session.state != .streaming
    }

    private var canSend: Bool {
        canType && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard let url = serverURL, let model, conversation != nil else { return }
        let text = draft
        draft = ""
        session.send(
            text: text,
            in: Binding(
                get: { conversation! },
                set: { conversation = $0 }
            ),
            model: model,
            baseURL: url
        )
    }
}

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(displayText)
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

    private var displayText: String {
        message.content.isEmpty && message.role == .assistant ? "…" : message.content
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
