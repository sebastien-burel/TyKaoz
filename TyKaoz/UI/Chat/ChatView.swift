import SwiftUI
import TyKaozKitMLX
import TyKaozKit
import MarkdownUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(MemoryStore.self) private var memory
    @Environment(WikiManager.self) private var wiki

    @Binding var conversation: Conversation?
    let provider: (any LLMProvider)?
    let providerID: String
    let tools: ToolRegistry

    @State private var session = ChatSession()
    /// Unsent input, kept per conversation (in memory) so switching
    /// conversations doesn't carry a half-written prompt across.
    @State private var drafts: [Conversation.ID: String] = [:]
    /// Images staged for the next message (VLM models only). Held in
    /// memory until send, then written to the conversation's attachment
    /// store. Cleared when switching conversations.
    @State private var pendingImages: [PendingImage] = []
    @State private var isImageImporterPresented = false
    /// Voice dictation session for the mic button; writes into the draft.
    @State private var dictation = DictationController()
    /// Drives keyboard focus on the message field so the user can type
    /// straight away: on opening a conversation and once a reply finishes.
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if conversation != nil {
                messagesScroll

                Divider().background(Brand.Colors.slate.opacity(0.15))
                inputBar
            } else {
                emptyState
            }
        }
        .background(Brand.Colors.paper)
        .toolbar {
            if let ctx = wiki.state.context, conversation != nil {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Cette conversation") {
                            wikifyConversation()
                        }
                        .disabled(conversation?.messages.isEmpty != false)

                        let sources = SourceImporter.recentSourceIDs(in: ctx.rawRoot)
                        if !sources.isEmpty {
                            Divider()
                            Section("Sources importées") {
                                ForEach(sources, id: \.self) { id in
                                    Button(id) { ingestSource(id, context: ctx) }
                                }
                            }
                        }
                    } label: {
                        Label("Wikifier", systemImage: "books.vertical")
                    }
                    .disabled(session.state == .streaming || provider == nil)
                    .help("Intègre au wiki cette conversation ou une source importée")
                }
            }
        }
        .onChange(of: session.state) { oldState, newState in
            if oldState == .streaming, newState == .idle {
                autoRenameIfNeeded()
                inputFocused = true   // hand focus back once the reply lands
            }
            if case .failed(let message) = newState {
                pruneActiveModelIfDeprecated(reportedBy: message)
            }
        }
        // Focus the field when a conversation opens or is switched to, and
        // retro-title any conversation still on the default name (e.g. an
        // older one whose first title attempt failed).
        .onChange(of: conversation?.id) { _, id in
            if id != nil { inputFocused = true }
            autoRenameIfNeeded()
        }
        .onAppear {
            if conversation != nil { inputFocused = true }
            autoRenameIfNeeded()
        }
    }

    /// Ingests an already-imported source (picked from the Wikifier menu):
    /// journals, then runs the ingest prompt through the normal chat loop.
    private func ingestSource(_ sourceID: String, context ctx: WikiContext) {
        guard let provider, conversation != nil else { return }
        WikiLog.append(op: "ingest", detail: sourceID, in: ctx.wikiRoot)
        session.send(
            text: WikiIngestPrompt.build(sourceID: sourceID),
            in: Binding(
                get: { conversation! },
                set: { conversation = $0 }
            ),
            using: provider,
            tools: tools,
            memoryContext: systemContext,
            model: activeModelLabel,
            store: store
        )
    }

    /// Ingest flow: snapshot the transcript into `raw/` (before the ingest
    /// turn is appended, so the mirror stays clean), journal + commit, then
    /// run the ingest prompt through the normal chat loop — tool calls stay
    /// visible and the user can interrupt.
    private func wikifyConversation() {
        guard let provider, let conv = conversation,
              let ctx = wiki.state.context,
              let sourceID = ConversationExporter.mirror(conv, into: ctx.rawRoot)
        else { return }
        WikiLog.append(op: "ingest", detail: "\(conv.title) → raw/\(sourceID).md", in: ctx.wikiRoot)
        GitRunner.commit(message: "ingest: mirror \(sourceID)", in: ctx.wikiRoot)
        session.send(
            text: WikiIngestPrompt.build(sourceID: sourceID),
            in: Binding(
                get: { conversation! },
                set: { conversation = $0 }
            ),
            using: provider,
            tools: tools,
            memoryContext: systemContext,
            model: activeModelLabel,
            store: store
        )
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
        case "anthropic": return settings.anthropicModel
        case "deepseek":  return settings.deepseekModel
        case "google":    return settings.googleModel
        case "localOpenAI": return settings.localOpenAIModel
        case "mlx":       return settings.mlxChatModelID
        case "mistral":   return settings.mistralModel
        case "ollama":    return settings.selectedModel
        case "openai":    return settings.openaiModel
        case "qwen":      return settings.qwenModel
        case "zai":       return settings.zaiModel
        default:          return nil
        }
    }

    /// If the conversation still has its default title and just got its
    /// first complete exchange, kick off a background title generation via
    /// the same provider. The first turn may include tool calls, so the
    /// message count can exceed 2 (user + assistant intro + tool call +
    /// tool result + assistant final…) — the `defaultTitle` guard handles
    /// re-entry.
    private func autoRenameIfNeeded() {
        guard let conv = conversation, let provider,
              session.state != .streaming,
              conv.title == ConversationTitler.defaultTitle,
              conv.messages.count >= 2
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
            let turns = conversation.turns
            let lastTurnID = turns.last?.id
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.decorate(turns), id: \.turn.id) { item in
                            if let marker = item.marker {
                                ModelMarker(label: marker)
                            }
                            TurnView(
                                turn: item.turn,
                                conversation: conversation,
                                isLive: item.turn.id == lastTurnID
                                    && session.state == .streaming
                            )
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
        VStack(alignment: .leading, spacing: 8) {
            if !pendingImages.isEmpty {
                pendingImagesStrip
            }
            if case .failed(let message, let isPermission) = dictation.phase {
                dictationErrorRow(message: message, isPermission: isPermission)
            }
            HStack(spacing: 8) {
                if supportsImages {
                    attachButton
                }
                micButton
                TextField(placeholder, text: draftBinding, axis: .vertical)
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
                    .focused($inputFocused)
                    .onSubmit(send)

                actionButton
            }
        }
        .padding(12)
        .background(Brand.Colors.paper)
        .fileImporter(
            isPresented: $isImageImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { importImages(from: urls) }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            guard supportsImages else { return false }
            return handleImageDrop(providers)
        }
        // ⌘V : intercept image paste before the focused text field eats it
        // (SwiftUI's onPasteCommand never fires while the field has focus).
        // Only claims the event when the clipboard holds an image and a VLM
        // is active, so plain text paste is untouched.
        .background(ImagePasteCatcher(isEnabled: supportsImages, onPaste: pasteImageFromClipboard))
        .onChange(of: conversation?.id) { _, _ in
            pendingImages = []
            dictation.cancel()
        }
    }

    /// The active model can take images. Drives the attach button, drop
    /// target and ⌘V paste so text-only models don't offer image input.
    /// MLX is gated precisely via the catalog's VLM flag; cloud providers
    /// whose modern models are multimodal are allowed at the provider
    /// level (a non-vision model there errors at request time).
    private var supportsImages: Bool {
        guard let model = activeModelForCurrentProvider(), !model.isEmpty else { return false }
        switch providerID {
        case "mlx":
            return ModelCatalogService.shared.entry(forID: model)?.isVision == true
        case "anthropic", "openai", "google":
            // Modern lineups are uniformly multimodal.
            return true
        case "mistral", "qwen", "zai":
            // Text and vision models coexist — gate on the model id. Qwen
            // image models also accept an input image (for editing); use the
            // client's own predicate so gating matches routing exactly.
            return Self.modelLooksMultimodal(model)
                || OpenAICompatibleClient.isQwenImageModel(model)
        default:
            return false
        }
    }

    /// Heuristic for providers that mix text and vision models. Vision ids
    /// carry recognisable markers: `-vl` (Qwen), `pixtral` / `mistral-small`
    /// / `mistral-medium` (Mistral), a digit+`v` suffix (z.ai GLM-4.5V…),
    /// or an explicit `vision`. A miss just hides the button; a false
    /// positive errors at request time.
    private static func modelLooksMultimodal(_ id: String) -> Bool {
        let s = id.lowercased()
        if s.contains("vl") || s.contains("vision") || s.contains("pixtral")
            || s.contains("mistral-small") || s.contains("mistral-medium") {
            return true
        }
        return s.range(of: #"[0-9]v"#, options: .regularExpression) != nil
    }

    private var attachButton: some View {
        Button {
            isImageImporterPresented = true
        } label: {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 20))
                .foregroundStyle(canType ? Brand.Colors.tide : Brand.Colors.slate.opacity(0.3))
        }
        .buttonStyle(.plain)
        .disabled(!canType)
        .help(maxImages == 1 ? "Joindre une image" : "Joindre des images")
    }

    @ViewBuilder
    private var micButton: some View {
        if dictation.phase == .finishing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24)
                .help("Transcription en cours…")
        } else {
            Button {
                dictation.toggle(
                    engineID: settings.transcriptionEngineID,
                    draft: draftBinding.wrappedValue
                ) { draftBinding.wrappedValue = $0 }
            } label: {
                Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 20))
                    .foregroundStyle(micColor)
            }
            .buttonStyle(.plain)
            .disabled(!canType)
            .help(dictation.isRecording ? "Arrêter la dictée" : "Dicter le message")
        }
    }

    private var micColor: Color {
        if dictation.isRecording { return Brand.Colors.ember }
        return canType ? Brand.Colors.tide : Brand.Colors.slate.opacity(0.3)
    }

    private func dictationErrorRow(message: String, isPermission: Bool) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(Brand.Fonts.body(11))
                .foregroundStyle(Brand.Colors.ember)
            if isPermission {
                Button("Ouvrir Réglages Système") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(Brand.Fonts.body(11))
            }
            Spacer()
        }
    }

    private var pendingImagesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { pending in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: pending.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Button {
                            pendingImages.removeAll { $0.id == pending.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white, Brand.Colors.ink.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .padding(2)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
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
            case "anthropic": return "Renseignez votre clé Anthropic et choisissez un modèle…"
            case "apple":     return "Apple Intelligence indisponible — voir les réglages."
            case "comfyui":   return "Configurez l'URL de votre serveur ComfyUI et ajoutez un workflow…"
            case "deepseek":  return "Renseignez votre clé DeepSeek et choisissez un modèle…"
            case "google":    return "Renseignez votre clé Google AI Studio et choisissez un modèle…"
            case "localOpenAI": return "Configurez l'URL de votre serveur (vLLM, LM Studio, llama.cpp) et choisissez un modèle…"
            case "mlx":       return "Choisis un modèle dans Réglages → Sur ce Mac et télécharge-le."
            case "mistral":   return "Renseignez votre clé Mistral et choisissez un modèle…"
            case "ollama":    return "Configurez Ollama (serveur + modèle) dans les réglages…"
            case "openai":    return "Renseignez votre clé OpenAI et choisissez un modèle…"
            case "qwen":      return "Renseignez votre clé Qwen Cloud et choisissez un modèle…"
            case "zai":       return "Renseignez votre clé z.ai et choisissez un modèle…"
            default:          return "Sélectionnez un provider dans les réglages…"
            }
        }
        return "Écrire un message…"
    }

    /// The current conversation's draft, read/written by the input field.
    /// Keyed by conversation id so each conversation keeps its own.
    private var draftBinding: Binding<String> {
        Binding(
            get: { conversation.flatMap { drafts[$0.id] } ?? "" },
            set: { if let id = conversation?.id { drafts[id] = $0 } }
        )
    }

    private var canType: Bool {
        provider != nil && conversation != nil && session.state != .streaming
    }

    private var canSend: Bool {
        canType && (!draftBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
    }

    private func send() {
        guard let provider, let conv = conversation else { return }
        let text = draftBinding.wrappedValue
        // Persist staged images to the conversation's attachment store; the
        // resulting metadata rides on the user message, the file URLs reach
        // the VLM via ChatSession → MLXChatActor.
        var attachments: [Message.Attachment] = []
        for pending in pendingImages {
            if let saved = store.saveAttachment(pending.data, conversationID: conv.id, ext: pending.ext) {
                attachments.append(saved)
            }
        }
        drafts[conv.id] = nil
        pendingImages = []
        session.send(
            text: text,
            in: Binding(
                get: { conversation! },
                set: { conversation = $0 }
            ),
            using: provider,
            tools: tools,
            memoryContext: systemContext,
            attachments: attachments,
            model: activeModelLabel,
            store: store
        )
    }

    /// System context for the next send: long-term memory plus, when the
    /// wiki is active, the wiki preamble (conventions + catalog +
    /// behavioral instructions). Apple Intelligence is excluded — its 4k
    /// window can't afford the preamble.
    private var systemContext: String? {
        var parts: [String] = []
        if settings.isToolEnabled("read_memory"),
           let memoryPart = memory.promptContext, !memoryPart.isEmpty {
            parts.append(memoryPart)
        }
        if settings.wikiContextEnabled,
           settings.isToolEnabled("search_wiki"),
           providerID != "apple",
           let ctx = wiki.state.context {
            let wikiPart = WikiPromptContext.load(
                wikiRoot: ctx.wikiRoot,
                autoCuration: settings.wikiAutoCuration
            )
            if !wikiPart.isEmpty { parts.append(wikiPart) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// "Provider · model" label for the active model, stamped on the user
    /// message so the transcript can flag where the model changed.
    private var activeModelLabel: String? {
        let providerName = ProviderID(providerID)?.displayName ?? providerID
        if let model = activeModelForCurrentProvider(), !model.isEmpty {
            return "\(providerName) · \(model)"
        }
        return providerName
    }

    /// Pairs each turn with a model label to display *above* it — set only
    /// on the first turn of a run on a given model (i.e. where the model
    /// differs from the previous turn's). Turns without a recorded model
    /// (older conversations) carry no marker and don't reset the tracking.
    static func decorate(
        _ turns: [Conversation.Turn]
    ) -> [(turn: Conversation.Turn, marker: String?)] {
        var out: [(turn: Conversation.Turn, marker: String?)] = []
        var lastModel: String?
        for turn in turns {
            let model = turn.userMessage.model
            let marker = (model != nil && model != lastModel) ? model : nil
            out.append((turn: turn, marker: marker))
            if model != nil { lastModel = model }
        }
        return out
    }

    /// Images per message: MLX VLMs (Gemma) accept a single image per
    /// prompt (mlx-swift-lm limitation); cloud vision models take several.
    private var maxImages: Int { providerID == "mlx" ? 1 : 6 }

    /// Stages one image, respecting `maxImages`. At a cap of 1 the latest
    /// replaces the previous; above 1 it accumulates until full.
    private func stage(_ pending: PendingImage) {
        if maxImages == 1 {
            pendingImages = [pending]
        } else if pendingImages.count < maxImages {
            pendingImages.append(pending)
        }
    }

    private func importImages(from urls: [URL]) {
        for url in urls {
            if maxImages > 1, pendingImages.count >= maxImages { break }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let pending = Self.makePendingImage(from: data) else { continue }
            stage(pending)
        }
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        let loadable = providers.filter { $0.canLoadObject(ofClass: NSImage.self) }
        guard !loadable.isEmpty else { return false }
        for provider in loadable {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage,
                      let tiff = image.tiffRepresentation,
                      let pending = Self.makePendingImage(from: tiff) else { return }
                Task { @MainActor in stage(pending) }
            }
        }
        return true
    }

    /// Stages an image from the general pasteboard (⌘V). No-op if the
    /// clipboard holds no image.
    private func pasteImageFromClipboard() {
        guard let image = NSImage(pasteboard: NSPasteboard.general),
              let tiff = image.tiffRepresentation,
              let pending = Self.makePendingImage(from: tiff) else { return }
        stage(pending)
    }

    /// Downscales to a 1536 px longest side and re-encodes to JPEG so
    /// attachments stay small. VLM processors resize internally anyway —
    /// this just caps what we store and feed.
    private static func makePendingImage(from data: Data, maxSide: CGFloat = 1536) -> PendingImage? {
        guard let source = NSImage(data: data),
              let tiff = source.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let width = CGFloat(rep.pixelsWide), height = CGFloat(rep.pixelsHigh)
        guard width > 0, height > 0 else { return nil }
        let scale = min(1, maxSide / max(width, height))
        let targetW = max(1, Int((width * scale).rounded()))
        let targetH = max(1, Int((height * scale).rounded()))
        guard let target = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: targetW, pixelsHigh: targetH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        target.size = NSSize(width: targetW, height: targetH)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
        source.draw(in: NSRect(x: 0, y: 0, width: targetW, height: targetH),
                    from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let jpeg = target.representation(using: .jpeg, properties: [.compressionFactor: 0.9]),
              let image = NSImage(data: jpeg) else { return nil }
        return PendingImage(data: jpeg, ext: "jpg", image: image)
    }
}

/// An image staged in the input bar before it's sent + persisted.
private struct PendingImage: Identifiable {
    let id = UUID()
    let data: Data
    let ext: String
    let image: NSImage
}

/// Invisible AppKit view that catches ⌘V at the view-hierarchy level —
/// before the focused text field's field editor consumes it. It only
/// claims the event when `isEnabled` (a VLM is active) and the clipboard
/// actually holds an image; otherwise it passes through so plain-text
/// paste behaves normally.
private struct ImagePasteCatcher: NSViewRepresentable {
    let isEnabled: Bool
    let onPaste: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.isEnabled = isEnabled
        view.onPaste = onPaste
    }

    final class CatcherView: NSView {
        var isEnabled = false
        var onPaste: (() -> Void)?

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if isEnabled,
               event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "v",
               NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil) {
                onPaste?()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}

private struct MessageBubble: View {
    let message: Message
    var imageURLs: [URL] = []

    @State private var reasoningExpanded = false

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if !imageURLs.isEmpty { attachmentThumbnails }
            if message.role == .assistant,
               let reasoning = message.reasoningContent,
               !reasoning.isEmpty {
                reasoningDisclosure(reasoning)
            }
            // No text bubble for an empty message — an in-flight assistant
            // shows the live streaming indicator instead of a "…" bubble,
            // and an image-only assistant just shows its thumbnail.
            if !message.content.isEmpty {
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
            }
            if message.role == .assistant, let metrics = message.metrics {
                MetricsFooter(metrics: metrics)
            }
            }
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        // Auto-expand the reasoning panel while the model is thinking (no
        // answer text yet), collapse it once the answer starts. The user
        // can still toggle a finished message manually.
        .onAppear {
            reasoningExpanded = message.content.isEmpty && hasReasoning
        }
        .onChange(of: message.reasoningContent) { _, _ in
            if message.content.isEmpty, hasReasoning { reasoningExpanded = true }
        }
        .onChange(of: message.content.isEmpty) { _, contentEmpty in
            if !contentEmpty { reasoningExpanded = false }
        }
    }

    private var hasReasoning: Bool {
        !(message.reasoningContent ?? "").isEmpty
    }

    /// Collapsible panel for a "thinking" model's chain of thought
    /// (Qwen 3 `<think>`, Gemma channel markers…). Captured but not part
    /// of the answer; collapsed by default.
    @ViewBuilder
    private func reasoningDisclosure(_ reasoning: String) -> some View {
        DisclosureGroup(isExpanded: $reasoningExpanded) {
            Text(reasoning)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 12))
                Text("Réflexion")
                    .font(Brand.Fonts.body(13))
            }
            .foregroundStyle(Brand.Colors.slate.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Brand.Colors.slate.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 520, alignment: .leading)
    }

    @ViewBuilder
    private var attachmentThumbnails: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            ForEach(imageURLs, id: \.self) { url in
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contextMenu {
                            Button("Enregistrer l'image…") { Self.saveImage(at: url) }
                            Button("Copier l'image") { Self.copyImage(at: url) }
                            Button("Afficher dans le Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                        .help("Clic droit pour enregistrer ou copier")
                }
            }
        }
    }

    /// Saves an attachment to a user-chosen location. Presented on the next
    /// run-loop tick (the context menu is still tearing down when the action
    /// fires, which can swallow a synchronous panel) and written via `Data`
    /// so the powerbox-granted write actually lands.
    private static func saveImage(at url: URL) {
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "TyKaoz-image.\(ext)"
            panel.canCreateDirectories = true
            if let type = UTType(filenameExtension: ext) {
                panel.allowedContentTypes = [type]
            }
            panel.begin { response in
                guard response == .OK, let dest = panel.url,
                      let data = try? Data(contentsOf: url) else { return }
                try? data.write(to: dest, options: .atomic)
            }
        }
    }

    private static func copyImage(at url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    /// Subtle inset color for fenced code blocks; contrasted with the bubble
    /// background.
    private var codeBackground: Color {
        switch message.role {
        case .user:
            return Brand.Colors.ink.opacity(0.4)
        case .assistant, .toolCall, .toolResult, .error:
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
        // Assistant text may carry LaTeX math the markdown engine can't
        // render; convert it to Unicode at display time (stored content
        // stays raw). User messages are shown verbatim.
        message.role == .assistant
            ? MathMarkup.render(message.content)
            : message.content
    }

    private var background: some ShapeStyle {
        switch message.role {
        case .user:                              return AnyShapeStyle(Brand.Colors.slate)
        case .assistant, .toolCall, .toolResult, .error: return AnyShapeStyle(Color.white)
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user:                              return Brand.Colors.paper
        case .assistant, .toolCall, .toolResult, .error: return Brand.Colors.ink
        }
    }

    private var borderColor: Color {
        switch message.role {
        case .user:                              return .clear
        case .assistant, .toolCall, .toolResult, .error: return Brand.Colors.slate.opacity(0.15)
        }
    }
}

/// Renders one user → assistant exchange. Intermediate steps (preamble
/// assistant texts + tool calls + tool results) live inside a disclosure
/// that's expanded while the turn is streaming and collapses automatically
/// once the turn ends.
private struct TurnView: View {
    @Environment(ConversationStore.self) private var store
    let turn: Conversation.Turn
    let conversation: Conversation
    let isLive: Bool

    /// Resolves a message's attachments (user uploads or model-generated
    /// images) to on-disk URLs for display.
    private func imageURLs(for message: Message) -> [URL] {
        (message.attachments ?? [])
            .map { store.attachmentURL(conversationID: conversation.id, $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MessageBubble(message: turn.userMessage, imageURLs: imageURLs(for: turn.userMessage))
                .id(turn.userMessage.id)

            if !turn.intermediates.isEmpty {
                IntermediateStepsDisclosure(
                    intermediates: turn.intermediates,
                    conversation: conversation,
                    isLive: isLive
                )
            }

            if let final = turn.finalAssistant {
                MessageBubble(message: final, imageURLs: imageURLs(for: final))
                    .id(final.id)
            }

            // While this turn is still running and no answer text has
            // arrived yet (waiting, reasoning or between tool rounds),
            // show a spinner with the elapsed time.
            if isLive && turn.finalAssistant == nil {
                StreamingIndicator(start: turn.userMessage.timestamp)
            }

            if let error = turn.error {
                ErrorBanner(message: error.content)
                    .id(error.id)
            }
        }
    }
}

/// Centered divider marking where the active model changed in the
/// transcript. Purely a visual cue derived from the user message's
/// `model` label; nothing here is sent to the LLM.
private struct ModelMarker: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            line
            Text(label)
                .font(Brand.Fonts.mono(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            line
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
    }

    private var line: some View {
        Rectangle()
            .fill(Brand.Colors.slate.opacity(0.15))
            .frame(height: 1)
    }
}

/// Animated "request in flight" indicator. Shows a spinner and, once the
/// turn has been running a couple of seconds, the elapsed time in
/// parentheses — like an agent runner.
private struct StreamingIndicator: View {
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(start)))
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(elapsed >= 2 ? "Génération… (\(elapsed) s)" : "Génération…")
                    .font(Brand.Fonts.body(12))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}

/// Compact performance line under an assistant answer: decode throughput,
/// token counts and time-to-first-token. Only fields the backend actually
/// reported are shown — aimed at benchmarking local servers (vLLM, NIM…)
/// where tok/s is the headline number.
private struct MetricsFooter: View {
    let metrics: GenerationMetrics

    var body: some View {
        let parts = segments
        if !parts.isEmpty {
            Text(parts.joined(separator: "  ·  "))
                .font(Brand.Fonts.mono(11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
    }

    private var segments: [String] {
        var s: [String] = []
        if let tps = metrics.tokensPerSecond {
            s.append(String(format: "%.1f tok/s", tps))
        }
        if let out = metrics.completionTokens {
            s.append("\(out) tok")
        }
        if let prompt = metrics.promptTokens {
            s.append("\(prompt) prompt")
        }
        if let pps = metrics.promptTokensPerSecond {
            s.append(String(format: "%.0f tok/s prefill", pps))
        }
        if let ttft = metrics.timeToFirstToken {
            s.append(ttft >= 1
                ? String(format: "TTFT %.2f s", ttft)
                : String(format: "TTFT %.0f ms", ttft * 1000))
        }
        return s
    }
}

/// Inline failure notice rendered where a send threw. Carries no link to
/// the LLM — it's a persisted `.error` message in the conversation.
private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(Brand.Colors.ink)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Copier l'erreur") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(message, forType: .string)
            }
        }
    }
}

private struct IntermediateStepsDisclosure: View {
    let intermediates: [Message]
    let conversation: Conversation
    let isLive: Bool

    @State private var isExpanded: Bool = false
    @State private var initialized = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(intermediates) { message in
                    intermediateRow(message)
                }
            }
            .padding(.top, 8)
            .padding(.leading, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12))
                Text(labelText)
                    .font(Brand.Fonts.body(13))
            }
            .foregroundStyle(Brand.Colors.slate.opacity(0.75))
        }
        .padding(.vertical, 4)
        .onAppear {
            guard !initialized else { return }
            isExpanded = isLive
            initialized = true
        }
        .onChange(of: isLive) { _, nowLive in
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded = nowLive
            }
        }
    }

    private var labelText: String {
        let toolCount = intermediates.filter { $0.role == .toolCall }.count
        switch toolCount {
        case 0:  return "Étapes intermédiaires"
        case 1:  return "1 outil utilisé"
        default: return "\(toolCount) outils utilisés"
        }
    }

    @ViewBuilder
    private func intermediateRow(_ message: Message) -> some View {
        switch message.role {
        case .toolCall:
            ToolCallCard(call: message, result: toolResult(for: message))
        case .toolResult:
            EmptyView()
        case .assistant:
            MessageBubble(message: message)
        case .user, .error:
            // `.error` is lifted out of `intermediates` by `turns` and
            // rendered as its own banner, so it never reaches here.
            EmptyView()
        }
    }

    private func toolResult(for call: Message) -> Message? {
        guard let id = call.toolCallID else { return nil }
        return conversation.messages.first {
            $0.role == .toolResult && $0.toolCallID == id
        }
    }
}
