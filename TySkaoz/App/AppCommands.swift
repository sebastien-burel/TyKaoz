import SwiftUI

/// Carries the active scene's "create a new conversation" action up to the
/// app's menu so Cmd-N can trigger it. The view that owns the sidebar
/// publishes its closure via `focusedSceneValue`.
struct NewConversationActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newConversationAction: NewConversationActionKey.Value? {
        get { self[NewConversationActionKey.self] }
        set { self[NewConversationActionKey.self] = newValue }
    }
}

/// Replaces the SwiftUI-default `.newItem` group so Cmd-N starts a new
/// conversation in the current window and Cmd-Shift-N opens a new window.
/// Adds a Wiki menu entry under "Window" so Cmd-Shift-K opens the wiki
/// browser as its own window.
struct AppCommands: Commands {
    @FocusedValue(\.newConversationAction) private var newConversation
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nouvelle conversation") {
                newConversation?()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newConversation == nil)

            Button("Nouvelle fenêtre") {
                openWindow(id: TySkaozApp.mainWindowID)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .windowArrangement) {
            Button("Wiki") {
                openWindow(id: TySkaozApp.wikiWindowID)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}
