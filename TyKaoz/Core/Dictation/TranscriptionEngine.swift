import Foundation

/// Events a dictation session produces. A `.partial` replaces the previous
/// partial (volatile hypothesis); a `.final` commits a segment for good.
enum TranscriptionEvent: Equatable, Sendable {
    case partial(String)
    case final(String)
}

/// A speech-to-text engine the dictation pipeline can drive. Mirrors the
/// `LLMProvider` shape (id + displayName + availability probe + one streaming
/// method) — no registry, engines are few and selected by id.
protocol TranscriptionEngine {
    var id: String { get }
    var displayName: String { get }

    func availability() async -> ProviderAvailability

    /// Transcribes a live audio stream of 16 kHz mono Float32 chunks.
    /// The audio stream ends when the mic stops; the returned stream
    /// finishes after the last `.final` has been emitted.
    func transcribe(_ audio: AsyncStream<[Float]>) -> AsyncThrowingStream<TranscriptionEvent, Error>
}

/// Engine lookup by settings id. Unknown ids fall back to Apple so a stale
/// stored value can never leave dictation without an engine.
func makeTranscriptionEngine(id: String) -> any TranscriptionEngine {
    switch id {
    case "parakeet": return ParakeetTranscriptionEngine()
    default:         return AppleTranscriptionEngine()
    }
}

enum DictationError: LocalizedError {
    case noMicrophone
    case unsupportedLocale

    var errorDescription: String? {
        switch self {
        case .noMicrophone:      return "Aucune entrée micro disponible."
        case .unsupportedLocale: return "Langue du système non prise en charge par la dictée."
        }
    }
}
