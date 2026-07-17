/// Pure state machine composing the message draft during a dictation
/// session: the text typed before recording stays untouched (`base`),
/// volatile partials are appended after it and replaced on every update,
/// finals are committed into the base.
struct DictationDraft: Equatable {
    /// Committed text: the pre-recording draft plus every `.final` so far.
    private(set) var base: String
    /// What the input field should display right now.
    private(set) var text: String

    init(base: String) {
        var base = base
        if !base.isEmpty && !base.hasSuffix(" ") {
            base += " "
        }
        self.base = base
        self.text = base
    }

    mutating func apply(_ event: TranscriptionEvent) {
        switch event {
        case .partial(let partial):
            text = base + partial
        case .final(let final):
            guard !final.isEmpty else {
                text = base
                return
            }
            base += final.hasSuffix(" ") ? final : final + " "
            text = base
        }
    }
}
import TyKaozKit
