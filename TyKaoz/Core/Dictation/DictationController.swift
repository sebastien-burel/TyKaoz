import AVFAudio
import Foundation
import Observation

/// Drives one dictation session end to end: mic permission, engine
/// availability, capture → transcription → draft updates. Owned by the
/// chat view; the mic button just calls `toggle`.
@Observable
@MainActor
final class DictationController {
    enum Phase: Equatable {
        case idle
        case recording
        /// Mic stopped, waiting for the engine's last finals (Parakeet
        /// transcribes the whole take here; Apple is near-instant).
        case failed(message: String, isPermission: Bool)
        case finishing
    }

    private(set) var phase: Phase = .idle

    private let recorder = MicRecorder()
    @ObservationIgnored private var pipeline: Task<Void, Never>?

    var isRecording: Bool { phase == .recording }

    /// Mic button entry point: starts a session, or stops the capture and
    /// lets the engine finalise. Ignored while a session is finalising.
    func toggle(engineID: String, draft: String, onText: @escaping (String) -> Void) {
        switch phase {
        case .recording:
            phase = .finishing
            recorder.stop()
        case .finishing:
            break
        case .idle, .failed:
            start(engineID: engineID, draft: draft, onText: onText)
        }
    }

    /// Abandons the session without committing anything (conversation
    /// switch, view teardown). Safe to call when idle.
    func cancel() {
        pipeline?.cancel()
        pipeline = nil
        recorder.stop()
        phase = .idle
    }

    private func start(engineID: String, draft: String, onText: @escaping (String) -> Void) {
        phase = .recording
        pipeline = Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                phase = .failed(
                    message: "Accès au micro refusé pour TyKaoz.",
                    isPermission: true
                )
                return
            }
            let engine = makeTranscriptionEngine(id: engineID)
            if case .unavailable(let reason) = await engine.availability() {
                phase = .failed(message: reason, isPermission: false)
                return
            }
            do {
                let audio = try recorder.start()
                var draft = DictationDraft(base: draft)
                for try await event in engine.transcribe(audio) {
                    guard !Task.isCancelled else { break }
                    draft.apply(event)
                    onText(draft.text)
                }
                if !Task.isCancelled { phase = .idle }
            } catch {
                recorder.stop()
                guard !Task.isCancelled else { return }
                phase = .failed(
                    message: "Dictée impossible : \(error.localizedDescription)",
                    isPermission: false
                )
            }
        }
    }
}
