import AVFAudio
import TyKaozKit

/// Captures the default input device and streams 16 kHz mono Float32
/// chunks — the least common denominator both engines consume (Parakeet
/// as-is, Apple re-wrapped into `AnalyzerInput` buffers).
@MainActor
final class MicRecorder {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<[Float]>.Continuation?

    func start() throws -> AsyncStream<[Float]> {
        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0,
              let converter = AVAudioConverter(from: nativeFormat, to: AudioResample.target16kMono) else {
            throw DictationError.noMicrophone
        }

        let (stream, continuation) = AsyncStream.makeStream(of: [Float].self)
        self.continuation = continuation
        // The tap fires on a realtime audio thread; conversion is cheap
        // enough to run there and keeps buffers off the main actor.
        input.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { buffer, _ in
            let samples = AudioResample.toMono16k(buffer, using: converter)
            if !samples.isEmpty {
                continuation.yield(samples)
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.continuation = nil
            throw error
        }
        return stream
    }

    /// Ends the capture and finishes the sample stream, letting the engine
    /// finalise its transcription. Safe to call when not recording.
    func stop() {
        guard continuation != nil else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }
}

/// Buffer math shared by the recorder and the engines. `nonisolated`:
/// called from the realtime audio tap, never touches shared state.
nonisolated enum AudioResample {
    /// 16 kHz mono Float32, non-interleaved — Parakeet's required input
    /// format and a format Apple's analyzer converts from without loss.
    static let target16kMono = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    /// Converts one tap buffer to 16 kHz mono samples. The converter is
    /// stateful (resampler filter memory) — pass the same instance for the
    /// whole capture session.
    static func toMono16k(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> [Float] {
        guard let out = convert(buffer, using: converter), let channel = out.floatChannelData else {
            return []
        }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
    }

    /// One-buffer-in, one-buffer-out conversion through an `AVAudioConverter`.
    static func convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            return nil
        }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0 else { return nil }
        return out
    }

    /// Re-wraps raw samples into a 16 kHz mono PCM buffer (Apple path).
    static func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: target16kMono, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
