import SwiftUI
import MarkdownUI

struct ChatView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @Binding var conversation: Conversation?
    let provider: (any LLMProvider)?
    let providerID: String
    let tools: ToolRegistry

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
        .onChange(of: session.state) { oldState, newState in
            if oldState == .streaming, newState == .idle {
                autoRenameIfNeeded()
            }
            if case .failed(let message) = newState {
                pruneActiveModelIfDeprecated(reportedBy: message)
            }
        }
    }

    /// Some providers list deprecated models in their catalog but 404 on
    /// use (Google is the worst offender — the API has no deprecation
    /// flag). When that happens, we recognise the pattern and uncheck the
    /// failing model so the picker stays honest. The user then picks a
    /// fresh one.
    private func pruneActiveModelIfDeprecated(reportedBy message: String) {
        let lower = message.lowercased()
        let deprecated = lower.contains("no longer available")
            || lower.contains("not found")
            || lower.contains("not_found")
            || lower.contains("model not found")
            || lower.contains("deprecated")
        guard deprecated,
              let provider = ProviderID(providerID),
              let active = activeModelForCurrentProvider() else { return }
        settings.setEnabled(false, modelID: active, for: provider)
    }

    private func activeModelForCurrentProvider() -> String? {
        switch providerID {
        case "ollama":    return settings.selectedModel
        case "mistral":   return settings.mistralModel
        case "openai":    return settings.openaiModel
        case "anthropic": return settings.anthropicModel
        case "google":    return settings.googleModel
        case "deepseek":  return settings.deepseekModel
        default:          return nil
        }
    }

    /// If the conversation still has its default title and just got its
    /// first complete exchange (1 user + 1 assistant), kick off a background
    /// title generation via the same provider. Snapshot the conversation so
    /// we update the right one even if the user navigates away.
    private func autoRenameIfNeeded() {
        guard let conv = conversation, let provider,
              conv.title == ConversationTitler.defaultTitle,
              conv.messages.count == 2
        else { return }

        let snapshot = conv
        Task {
            guard let title = await ConversationTitler.generate(from: snapshot, using: provider) else { return }
            var updated = snapshot
            updated.title = title
            store.update(updated)
        }
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
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .contextMenu {
            Button("Copier l'erreur") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(message, forType: .string)
            }
        }
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
        if provider == nil {
            switch providerID {
            case "ollama":    return "Configurez Ollama (serveur + modèle) dans les réglages…"
            case "mistral":   return "Renseignez votre clé Mistral et choisissez un modèle…"
            case "openai":    return "Renseignez votre clé OpenAI et choisissez un modèle…"
            case "anthropic": return "Renseignez votre clé Anthropic et choisissez un modèle…"
            case "google":    return "Renseignez votre clé Google AI Studio et choisissez un modèle…"
            case "deepseek":  return "Renseignez votre clé DeepSeek et choisissez un modèle…"
            case "apple":     return "Apple Intelligence indisponible — voir les réglages."
            default:          return "Sélectionnez un provider dans les réglages…"
            }
        }
        return "Écrire un message…"
    }

    private var canType: Bool {
        provider != nil && conversation != nil && session.state != .streaming
    }

    private var canSend: Bool {
        canType && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard let provider, conversation != nil else { return }
        let text = draft
        draft = ""
        session.send(
            text: text,
            in: Binding(
                get: { conversation! },
                set: { conversation = $0 }
            ),
            using: provider,
            tools: tools
        )
    }
}

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Markdown(displayText)
                .markdownTextStyle {
                    FontFamily(.custom("Inter Tight"))
                    FontSize(14)
                    ForegroundColor(textColor)
                }
                .markdownBlockStyle(\.paragraph) { configuration in
                    configuration.label
                        .lineSpacing(4)
                        .padding(.bottom, 4)
                }
                .markdownBlockStyle(\.listItem) { configuration in
                    configuration.label
                        .lineSpacing(4)
                        .padding(.bottom, 2)
                }
                .markdownBlockStyle(\.heading1) { configuration in
                    configuration.label
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                .markdownBlockStyle(\.heading2) { configuration in
                    configuration.label
                        .padding(.top, 6)
                        .padding(.bottom, 3)
                }
                .markdownBlockStyle(\.heading3) { configuration in
                    configuration.label
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .padding(10)
                        .background(codeBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .markdownTextStyle {
                            FontFamily(.custom("JetBrains Mono"))
                            FontSize(12)
                            ForegroundColor(textColor)
                        }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    Button("Copier le message") { copyToPasteboard(message.content) }
                        .disabled(message.content.isEmpty)
                }
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    /// Subtle inset color for fenced code blocks; contrasted with the bubble
    /// background.
    private var codeBackground: Color {
        switch message.role {
        case .user:
            return Brand.Colors.ink.opacity(0.4)
        case .assistant, .toolCall, .toolResult:
            // Tool messages will get their own dedicated card view in Bloc 6;
            // this branch keeps the switch exhaustive in the meantime.
            return Brand.Colors.slate.opacity(0.08)
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private var displayText: String {
        message.content.isEmpty && message.role == .assistant ? "…" : message.content
    }

    private var background: some ShapeStyle {
        switch message.role {
        case .user:                              return AnyShapeStyle(Brand.Colors.slate)
        case .assistant, .toolCall, .toolResult: return AnyShapeStyle(Color.white)
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user:                              return Brand.Colors.paper
        case .assistant, .toolCall, .toolResult: return Brand.Colors.ink
        }
    }

    private var borderColor: Color {
        switch message.role {
        case .user:                              return .clear
        case .assistant, .toolCall, .toolResult: return Brand.Colors.slate.opacity(0.15)
        }
    }
}
