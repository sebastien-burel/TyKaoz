import AVFAudio
import Foundation
import Testing
@testable import TyKaoz

struct DictationDraftTests {
    @Test
    func partialsReplaceEachOther() {
        var draft = DictationDraft(base: "")
        draft.apply(.partial("bon"))
        #expect(draft.text == "bon")
        draft.apply(.partial("bonjour"))
        #expect(draft.text == "bonjour")
    }

    @Test
    func finalCommitsAndNextPartialAppends() {
        var draft = DictationDraft(base: "")
        draft.apply(.partial("bonjou"))
        draft.apply(.final("bonjour"))
        #expect(draft.text == "bonjour ")
        draft.apply(.partial("tout le"))
        #expect(draft.text == "bonjour tout le")
        draft.apply(.final("tout le monde"))
        #expect(draft.text == "bonjour tout le monde ")
    }

    @Test
    func nonEmptyBaseGetsSeparatingSpace() {
        var draft = DictationDraft(base: "Déjà tapé")
        #expect(draft.text == "Déjà tapé ")
        draft.apply(.partial("suite"))
        #expect(draft.text == "Déjà tapé suite")
    }

    @Test
    func baseEndingInSpaceIsKeptAsIs() {
        let draft = DictationDraft(base: "Déjà tapé ")
        #expect(draft.text == "Déjà tapé ")
    }

    @Test
    func emptyFinalDropsPendingPartial() {
        var draft = DictationDraft(base: "")
        draft.apply(.partial("euh"))
        draft.apply(.final(""))
        #expect(draft.text == "")
    }
}

struct AudioResampleTests {
    /// 48 kHz stereo sine, converted: ~1/3 of the frames, mono, non-silent.
    @Test
    func downsamples48kStereoToMono16k() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false
        )!
        let frames: AVAudioFrameCount = 4800
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            let data = buffer.floatChannelData![channel]
            for i in 0..<Int(frames) {
                data[i] = sinf(2 * .pi * 440 * Float(i) / 48_000)
            }
        }
        let converter = try #require(AVAudioConverter(from: format, to: AudioResample.target16kMono))

        let samples = AudioResample.toMono16k(buffer, using: converter)

        // 4800 frames @48k ≈ 1600 @16k; the resampler filter delay may
        // hold back a handful of frames on the first call.
        #expect(samples.count > 1300 && samples.count <= 1600)
        #expect(samples.contains { abs($0) > 0.1 })
    }

    @Test
    func silenceStaysSilent() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        buffer.frameLength = 4800
        let converter = try #require(AVAudioConverter(from: format, to: AudioResample.target16kMono))

        let samples = AudioResample.toMono16k(buffer, using: converter)

        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { abs($0) < 0.001 })
    }

    @Test
    func makeBufferRoundTripsSamples() {
        let samples: [Float] = [0.1, -0.2, 0.3, 0]
        let buffer = AudioResample.makeBuffer(samples)!
        #expect(buffer.frameLength == 4)
        #expect(buffer.format.sampleRate == 16_000)
        #expect(buffer.format.channelCount == 1)
        let out = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 4))
        #expect(out == samples)
        #expect(AudioResample.makeBuffer([]) == nil)
    }
}

struct ParakeetUpdateFolderTests {
    /// Volatile hypotheses replace each other after the confirmed prefix;
    /// confirmed windows accumulate for good.
    @Test
    func volatileReplacesConfirmedAccumulates() {
        var folder = ParakeetUpdateFolder()
        #expect(folder.fold(text: "bonjour", isConfirmed: false) == "bonjour")
        #expect(folder.fold(text: "bonjour tout", isConfirmed: false) == "bonjour tout")
        #expect(folder.fold(text: "bonjour tout le monde", isConfirmed: true) == "bonjour tout le monde")
        #expect(folder.fold(text: "et la", isConfirmed: false) == "bonjour tout le monde et la")
        #expect(folder.fold(text: "et la suite", isConfirmed: false) == "bonjour tout le monde et la suite")
        #expect(folder.fold(text: "et la suite.", isConfirmed: true) == "bonjour tout le monde et la suite.")
    }

    @Test
    func emptyOrBlankUpdatesAreDropped() {
        var folder = ParakeetUpdateFolder()
        #expect(folder.fold(text: "", isConfirmed: false) == nil)
        #expect(folder.fold(text: "  ", isConfirmed: true) == nil)
        #expect(folder.fold(text: " ok ", isConfirmed: false) == "ok")
    }
}
