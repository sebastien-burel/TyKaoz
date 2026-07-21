import SwiftUI
import AppKit

/// A plain-text code editor backed by `NSTextView` with every automatic text
/// substitution turned off, so code stays verbatim. SwiftUI's `TextEditor`
/// inherits the system "smart quotes / dashes" setting, which rewrites
/// `import { Hello } from "prompts"` into curly quotes (`« prompts »` in a
/// French locale) — fatal for source. Scoped to the agent editor so chat prose
/// keeps its typographic substitutions.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 12

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true

        // The whole point: no automatic rewriting of what the user types.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .black                 // legible on the editor's white background
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.drawsBackground = false            // let the SwiftUI background show through
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        // Only push external changes (e.g. switching the selected agent); never
        // during the user's own edits, which would fight the cursor.
        if textView.string != text {
            textView.string = text
        }
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
