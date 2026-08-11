// Copyright Sierra

import UIKit
import XCTest
@testable import SierraChatKit
@testable import SierraSDKVoice

/// Sample rate the SDK's voice pipeline runs at, and so the rate these bands are analysed at.
private let voiceSampleRate: Double = 24000

/// Fills a buffer with a unit-amplitude sine whose period is an exact number of samples, so it lands
/// on the center of FFT bin `bin` for a 64-point transform.
private func sineAtBin(_ bin: Int, sampleCount: Int = 64) -> [Float] {
    (0..<sampleCount).map { index in
        sinf(2 * Float.pi * Float(bin) * Float(index) / 64)
    }
}

private func indexOfMaximum(_ levels: [Float]) -> Int {
    var best = 0
    for (index, level) in levels.enumerated() where level > levels[best] {
        best = index
    }
    return best
}

final class VoiceWaveformScaleTests: XCTestCase {
    func testClampsScaleIntoTheSupportedRange() {
        XCTAssertEqual(clampedVoiceWaveformScale(1), 1)
        XCTAssertEqual(clampedVoiceWaveformScale(0.5), 0.5)
        XCTAssertEqual(clampedVoiceWaveformScale(10), VOICE_WAVEFORM_SCALE_MAX)
        XCTAssertEqual(clampedVoiceWaveformScale(-1), VOICE_WAVEFORM_SCALE_MIN)
    }

    func testFallsBackToTheDefaultForNonFiniteScales() {
        XCTAssertEqual(clampedVoiceWaveformScale(.nan), DEFAULT_VOICE_WAVEFORM_SCALE)
        XCTAssertEqual(clampedVoiceWaveformScale(.infinity), DEFAULT_VOICE_WAVEFORM_SCALE)
    }

    @MainActor
    func testWaveformSizeScalesBarsAndSpacingTogether() {
        // Eight 4pt bars separated by seven 2pt gaps, 32pt tall, all multiplied by the scale.
        let view = VoiceWaveformView()

        XCTAssertEqual(view.intrinsicContentSize, CGSize(width: 46, height: 32))

        view.scale = 2
        XCTAssertEqual(view.intrinsicContentSize, CGSize(width: 92, height: 64))

        view.scale = 0.5
        XCTAssertEqual(view.intrinsicContentSize, CGSize(width: 23, height: 16))
    }

    @MainActor
    func testWaveformSizeIsClampedByTheView() {
        let view = VoiceWaveformView()

        view.scale = 10
        XCTAssertEqual(view.scale, VOICE_WAVEFORM_SCALE_MAX)
        XCTAssertEqual(view.intrinsicContentSize, CGSize(width: 138, height: 96))

        view.scale = -1
        XCTAssertEqual(view.scale, VOICE_WAVEFORM_SCALE_MIN)
        XCTAssertEqual(view.intrinsicContentSize, .zero)
    }

    @MainActor
    func testWaveformDefaultsToTheWebSDKColors() {
        let view = VoiceWaveformView()

        XCTAssertEqual(view.agentColor, DEFAULT_VOICE_WAVEFORM_AGENT_COLOR)
        XCTAssertEqual(view.userColor, DEFAULT_VOICE_WAVEFORM_USER_COLOR)
    }
}

final class VoiceWaveformSmoothingTests: XCTestCase {
    func testFirstSampleSnapsInsteadOfAttackingFromZero() {
        var smoother = VoiceWaveformLevelSmoother()
        let first = [CGFloat](repeating: 0.75, count: VOICE_WAVEFORM_BAR_COUNT)

        smoother.step(toward: first)

        XCTAssertEqual(smoother.displayedLevels, first)
    }

    func testZeroFirstSampleStillInitializesSmoothingState() {
        var smoother = VoiceWaveformLevelSmoother()
        smoother.step(toward: [CGFloat](repeating: 0, count: VOICE_WAVEFORM_BAR_COUNT))

        smoother.step(toward: [CGFloat](repeating: 1, count: VOICE_WAVEFORM_BAR_COUNT))

        XCTAssertEqual(smoother.displayedLevels[0], 0.62, accuracy: 0.0001)
    }

    func testSubsequentSamplesUseWebAttackAndReleaseCoefficients() {
        var smoother = VoiceWaveformLevelSmoother()
        smoother.step(toward: [CGFloat](repeating: 0.2, count: VOICE_WAVEFORM_BAR_COUNT))

        smoother.step(toward: [CGFloat](repeating: 1, count: VOICE_WAVEFORM_BAR_COUNT))
        XCTAssertEqual(smoother.displayedLevels[0], 0.696, accuracy: 0.0001)

        smoother.step(toward: [CGFloat](repeating: 0, count: VOICE_WAVEFORM_BAR_COUNT))
        XCTAssertEqual(smoother.displayedLevels[0], 0.51504, accuracy: 0.0001)
    }

    func testResetRestoresFirstSampleSnapSemantics() {
        var smoother = VoiceWaveformLevelSmoother()
        smoother.step(toward: [CGFloat](repeating: 1, count: VOICE_WAVEFORM_BAR_COUNT))
        smoother.reset()

        let resumed = [CGFloat](repeating: 0.4, count: VOICE_WAVEFORM_BAR_COUNT)
        smoother.step(toward: resumed)

        XCTAssertEqual(smoother.displayedLevels, resumed)
    }
}

final class AudioSpectrumAnalyserTests: XCTestCase {
    func testSilenceRestsEveryBandAtZero() {
        let analyser = AudioSpectrumAnalyser()
        let silence = [Float](repeating: 0, count: 64)

        let levels = silence.withUnsafeBufferPointer {
            analyser.analyse(samples: $0.baseAddress!, count: 64)
        }

        XCTAssertEqual(levels.count, VOICE_WAVEFORM_BAR_COUNT)
        XCTAssertEqual(levels, AudioSpectrumAnalyser.restingLevels())
    }

    /// A tone at a kept bin's center frequency must light that band, not a neighbor -- this is what
    /// makes the eight bars respond independently rather than moving as one.
    func testAToneLightsTheBandItBelongsTo() {
        // Bin 8 is the third band the web waveform keeps; at 24 kHz that is 3 kHz.
        let bin = 8
        let expectedBand = 2
        XCTAssertEqual(Double(bin) * voiceSampleRate / 64, 3000)

        let analyser = AudioSpectrumAnalyser()
        let tone = sineAtBin(bin)
        var levels = [Float]()
        // The analyser smooths across calls the way the Web Audio node does, so let it settle.
        for _ in 0..<20 {
            levels = tone.withUnsafeBufferPointer {
                analyser.analyse(samples: $0.baseAddress!, count: tone.count)
            }
        }

        XCTAssertEqual(indexOfMaximum(levels), expectedBand)
        XCTAssertGreaterThan(levels[expectedBand], 0.9)
        // A band six bins away from the tone stays quiet; the Blackman window keeps leakage low.
        XCTAssertLessThan(levels[0], 0.5)
    }

    func testResetClearsSmoothedLevels() {
        let analyser = AudioSpectrumAnalyser()
        let tone = sineAtBin(8)
        for _ in 0..<20 {
            _ = tone.withUnsafeBufferPointer {
                analyser.analyse(samples: $0.baseAddress!, count: tone.count)
            }
        }

        analyser.reset()
        let silence = [Float](repeating: 0, count: 64)
        let levels = silence.withUnsafeBufferPointer {
            analyser.analyse(samples: $0.baseAddress!, count: 64)
        }

        XCTAssertEqual(levels, AudioSpectrumAnalyser.restingLevels())
    }

    func testSilenceDecaysWithoutResettingAnalyserHistory() {
        let analyser = AudioSpectrumAnalyser()
        let tone = sineAtBin(8)
        var toneLevels = [Float]()
        for _ in 0..<20 {
            toneLevels = tone.withUnsafeBufferPointer {
                analyser.analyse(samples: $0.baseAddress!, count: tone.count)
            }
        }

        let silence = [Float](repeating: 0, count: 64)
        var decayingLevels = [Float]()
        for _ in 0..<10 {
            decayingLevels = silence.withUnsafeBufferPointer {
                analyser.analyse(samples: $0.baseAddress!, count: silence.count)
            }
        }

        XCTAssertGreaterThan(decayingLevels[2], 0)
        XCTAssertLessThan(decayingLevels[2], toneLevels[2])
    }

    func testLevelsUseWebByteNormalization() {
        let analyser = AudioSpectrumAnalyser()
        let tone = sineAtBin(8)

        let levels = tone.withUnsafeBufferPointer {
            analyser.analyse(samples: $0.baseAddress!, count: tone.count)
        }

        for level in levels {
            XCTAssertEqual(level * 255, (level * 255).rounded(), accuracy: 0.0001)
        }
    }

    /// The capture path analyses the converted linear16 buffer, so the Int16 entry point has to
    /// agree with the float one for the same signal.
    func testInt16InputMatchesFloatInput() {
        let tone = sineAtBin(8)
        let samples = tone.map { Int16(($0 * 32767).rounded()) }

        let floatAnalyser = AudioSpectrumAnalyser()
        let int16Analyser = AudioSpectrumAnalyser()
        var floatLevels = [Float]()
        var int16Levels = [Float]()
        for _ in 0..<20 {
            floatLevels = tone.withUnsafeBufferPointer {
                floatAnalyser.analyse(samples: $0.baseAddress!, count: tone.count)
            }
            int16Levels = samples.withUnsafeBufferPointer {
                int16Analyser.analyse(samples: $0.baseAddress!, count: samples.count)
            }
        }

        for band in 0..<VOICE_WAVEFORM_BAR_COUNT {
            XCTAssertEqual(floatLevels[band], int16Levels[band], accuracy: 0.01)
        }
    }

    /// A read shorter than the 64-sample window still transforms a full window, by carrying over the
    /// tail of the previous read.
    func testShortReadsStillFillTheWindow() {
        let analyser = AudioSpectrumAnalyser()
        let tone = sineAtBin(8, sampleCount: 256)
        var levels = [Float]()
        for chunkStart in stride(from: 0, to: tone.count, by: 16) {
            let chunk = Array(tone[chunkStart..<(chunkStart + 16)])
            levels = chunk.withUnsafeBufferPointer {
                analyser.analyse(samples: $0.baseAddress!, count: chunk.count)
            }
        }

        XCTAssertEqual(indexOfMaximum(levels), 2)
    }
}

final class VoiceWaveformCadenceTests: XCTestCase {
    func testInputTapRequestsTwentyMillisecondBuffers() {
        XCTAssertEqual(
            AudioCaptureSession.inputTapBufferSize(sampleRate: voiceSampleRate, duration: 0.02),
            480
        )
        XCTAssertEqual(
            AudioCaptureSession.inputTapBufferSize(sampleRate: 48000, duration: 0.02),
            960
        )
    }

    func testPlaybackTapRequestsTwentyMillisecondBuffers() {
        XCTAssertEqual(
            VoiceSessionManager.waveformTapBufferSize(sampleRate: voiceSampleRate, interval: 0.02),
            480
        )
    }
}
