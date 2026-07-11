import AVFAudio
import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT 0.6b v3 (multilingue) via FluidAudio — CoreML sur le
/// Neural Engine. Transcrit en pseudo-streaming (fenêtres glissantes) : des
/// hypothèses arrivent toutes les ~1 s pendant la prise, puis `finish()`
/// fournit le transcript complet, seule version committée (`.final`) — les
/// hypothèses ne sont jamais committées, donc pas de duplication possible.
struct ParakeetTranscriptionEngine: TranscriptionEngine {
    let id = "parakeet"
    let displayName = "Parakeet V3 (sur ce Mac)"

    func availability() async -> ProviderAvailability {
        ParakeetASR.isInstalled
            ? .ready
            : .unavailable(reason: "Modèle Parakeet non téléchargé — Réglages → Dictée.")
    }

    func transcribe(_ audio: AsyncStream<[Float]>) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var updatesTask: Task<Void, Never>?
                do {
                    let models = try await ParakeetASR.shared.loadedModels()
                    let manager = SlidingWindowAsrManager(config: .streaming)
                    try await manager.loadModels(models)
                    try await manager.startStreaming(source: .microphone)

                    let updates = await manager.transcriptionUpdates
                    updatesTask = Task {
                        var folder = ParakeetUpdateFolder()
                        for await update in updates {
                            if let partial = folder.fold(text: update.text, isConfirmed: update.isConfirmed) {
                                continuation.yield(.partial(partial))
                            }
                        }
                    }

                    for await samples in audio {
                        guard let buffer = AudioResample.makeBuffer(samples) else { continue }
                        await manager.streamAudio(buffer)
                    }

                    let finalText = try await manager.finish()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    updatesTask?.cancel()
                    if !finalText.isEmpty {
                        continuation.yield(.final(finalText))
                    }
                    continuation.finish()
                } catch {
                    updatesTask?.cancel()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Folds sliding-window updates into one cumulative display string. Each
/// update carries only its window's text: confirmed windows accumulate,
/// the volatile hypothesis is appended after them and replaced on every
/// update. Pure state machine, kept out of the engine for testing.
struct ParakeetUpdateFolder: Equatable {
    private(set) var confirmed = ""

    /// Returns the cumulative text to display, nil when the update is empty.
    mutating func fold(text: String, isConfirmed: Bool) -> String? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let cumulative = confirmed.isEmpty ? text : confirmed + " " + text
        if isConfirmed {
            confirmed = cumulative
        }
        return cumulative
    }
}

/// Owns the FluidAudio model bundle: download and memoised load, shared by
/// every dictation session so CoreML compilation happens once.
actor ParakeetASR {
    static let shared = ParakeetASR()

    private var models: AsrModels?

    /// Models on disk (app container, Application Support/FluidAudio) —
    /// cheap check for availability and the settings pane.
    static var isInstalled: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3))
    }

    /// Downloads the v3 CoreML bundles from Hugging Face (~1 Go). Serves
    /// the on-disk cache when already present.
    static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await AsrModels.download(version: .v3) { update in
            progress(update.fractionCompleted)
        }
    }

    func loadedModels() async throws -> AsrModels {
        if let models { return models }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        self.models = models
        return models
    }
}
