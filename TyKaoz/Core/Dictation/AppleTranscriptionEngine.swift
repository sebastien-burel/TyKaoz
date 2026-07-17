import AVFAudio
import TyKaozKit
import Foundation
import Speech

/// Apple on-device dictation via the macOS 26 `SpeechAnalyzer` stack.
/// Streams volatile partials live, commits finals as segments settle.
/// The language model is a system asset, installed from the settings pane.
struct AppleTranscriptionEngine: TranscriptionEngine {
    let id = "apple"
    let displayName = "Apple (sur ce Mac)"

    /// Dictation locale matching the system language, nil when unsupported.
    static func matchedLocale() async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: .current)
    }

    static func assetsInstalled() async -> Bool {
        guard let locale = await matchedLocale() else { return false }
        return await SpeechTranscriber.installedLocales.contains {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }
    }

    /// Downloads the on-device dictation model for the system language.
    /// No-op when the model is already installed (the request comes back nil).
    static func installAssets() async throws {
        guard let locale = await matchedLocale() else {
            throw DictationError.unsupportedLocale
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    func availability() async -> ProviderAvailability {
        guard await Self.matchedLocale() != nil else {
            return .unavailable(reason: "La dictée Apple ne prend pas en charge la langue du système.")
        }
        guard await Self.assetsInstalled() else {
            return .unavailable(reason: "Modèle de dictée non installé — Réglages → Dictée.")
        }
        return .ready
    }

    func transcribe(_ audio: AsyncStream<[Float]>) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let locale = await Self.matchedLocale() else {
                        throw DictationError.unsupportedLocale
                    }
                    let transcriber = SpeechTranscriber(
                        locale: locale,
                        transcriptionOptions: [],
                        reportingOptions: [.volatileResults],
                        attributeOptions: []
                    )
                    let analyzer = SpeechAnalyzer(modules: [transcriber])
                    // The analyzer wants its own preferred format; convert
                    // from the pipeline's 16 kHz mono when they differ.
                    let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [transcriber]
                    ) ?? AudioResample.target16kMono
                    let converter = analyzerFormat == AudioResample.target16kMono
                        ? nil
                        : AVAudioConverter(from: AudioResample.target16kMono, to: analyzerFormat)

                    let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
                    try await analyzer.start(inputSequence: inputSequence)

                    // Feed mic chunks until the recorder stops, then ask the
                    // analyzer to finalise — that ends `transcriber.results`.
                    let pump = Task {
                        for await samples in audio {
                            guard var buffer = AudioResample.makeBuffer(samples) else { continue }
                            if let converter {
                                guard let converted = AudioResample.convert(buffer, using: converter) else { continue }
                                buffer = converted
                            }
                            inputBuilder.yield(AnalyzerInput(buffer: buffer))
                        }
                        inputBuilder.finish()
                        try await analyzer.finalizeAndFinishThroughEndOfInput()
                    }

                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        guard !text.isEmpty else { continue }
                        continuation.yield(result.isFinal ? .final(text) : .partial(text))
                    }
                    try await pump.value
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
