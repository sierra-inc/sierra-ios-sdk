// Copyright Sierra

import AVFoundation
import Foundation

/// Turns PCM audio into the per-band levels the voice waveform draws.
///
/// Reproduces what the Web SDK gets from a Web Audio `AnalyserNode` with `fftSize = 64`, so the
/// native waveform behaves like the web one: a Blackman-windowed 64-point FFT, magnitudes smoothed
/// over time, converted to decibels across a -100...-30 dB window, then sampled at the same eight
/// bins the web waveform keeps. Levels come back normalized to `0...1`.
///
/// Bin index (not absolute frequency) is what is held in common with web, because a browser's
/// `AudioContext` sample rate is itself device-dependent. At the SDK's 24 kHz voice sample rate the
/// eight bands span roughly 750 Hz to 9 kHz.
///
/// Instances are normally audio-thread confined. Calls are synchronized so playback completion
/// can reset the output analyser even when AVAudioPlayerNode stops delivering tap buffers.
final class AudioSpectrumAnalyser {
    /// Matches the Web SDK's `AnalyserNode.fftSize`, which yields 32 usable bins.
    private static let fftSize = 64
    private static let keptBins = [2, 5, 8, 11, 14, 17, 20, 24]

    /// `AnalyserNode` defaults, which set how magnitudes are smoothed and mapped onto `0...255`.
    private static let smoothingTimeConstant: Float = 0.8
    private static let minDecibels: Float = -100
    private static let maxDecibels: Float = -30

    /// Blackman window coefficients from the Web Audio specification.
    private static let window: [Float] = (0..<fftSize).map { index in
        let ratio = 2 * Float.pi * Float(index) / Float(fftSize)
        return 0.42 - 0.5 * cos(ratio) + 0.08 * cos(2 * ratio)
    }

    private var samples = [Float](repeating: 0, count: fftSize)
    private var real = [Float](repeating: 0, count: fftSize)
    private var imaginary = [Float](repeating: 0, count: fftSize)
    private var smoothedMagnitudes = [Float](repeating: 0, count: keptBins.count)
    private let lock = NSLock()

    /// Per-band levels for the most recent `fftSize` samples ending at this buffer, each `0...1`.
    func analyse(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return Self.restingLevels() }
        return analyse(samples: channel, count: Int(buffer.frameLength))
    }

    /// Per-band levels for a signed-16-bit buffer, used for the linear16 transport format the SDK
    /// captures and plays.
    func analyse(samples newSamples: UnsafePointer<Int16>, count: Int) -> [Float] {
        guard count > 0 else { return Self.restingLevels() }
        let taken = min(count, Self.fftSize)
        let offset = count - taken
        var floatSamples = [Float](repeating: 0, count: taken)
        for index in 0..<taken {
            floatSamples[index] = Float(newSamples[offset + index]) / 32768
        }
        return floatSamples.withUnsafeBufferPointer { buffer in
            analyse(samples: buffer.baseAddress!, count: taken)
        }
    }

    func analyse(samples newSamples: UnsafePointer<Float>, count: Int) -> [Float] {
        guard count > 0 else { return Self.restingLevels() }
        lock.lock()
        defer { lock.unlock() }
        appendSamples(newSamples, count: count)

        for index in 0..<Self.fftSize {
            real[index] = samples[index] * Self.window[index]
            imaginary[index] = 0
        }
        forwardTransform()

        return Self.keptBins.enumerated().map { position, bin in
            let magnitude = (real[bin] * real[bin] + imaginary[bin] * imaginary[bin]).squareRoot()
                / Float(Self.fftSize)
            let smoothed = Self.smoothingTimeConstant * smoothedMagnitudes[position]
                + (1 - Self.smoothingTimeConstant) * magnitude
            smoothedMagnitudes[position] = smoothed
            return Self.normalizedLevel(magnitude: smoothed)
        }
    }

    /// Clears the smoothing state and sample window so a resumed stream doesn't decay out of stale
    /// levels.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        for index in 0..<Self.fftSize {
            samples[index] = 0
        }
        for index in 0..<smoothedMagnitudes.count {
            smoothedMagnitudes[index] = 0
        }
    }

    /// Levels for silence. Static so suppression paths can emit it without touching analyser state.
    static func restingLevels() -> [Float] {
        [Float](repeating: 0, count: keptBins.count)
    }

    /// Keeps `samples` holding the most recent `fftSize` samples of the stream, so a tap buffer
    /// shorter than the window still transforms a full window.
    private func appendSamples(_ newSamples: UnsafePointer<Float>, count: Int) {
        let taken = min(count, Self.fftSize)
        let retained = Self.fftSize - taken
        if retained > 0 {
            for index in 0..<retained {
                samples[index] = samples[index + taken]
            }
        }
        let offset = count - taken
        for index in 0..<taken {
            samples[retained + index] = newSamples[offset + index]
        }
    }

    /// Maps a magnitude through Web Audio's byte-valued `getByteFrequencyData`, then normalizes the
    /// byte back onto `0...1` for the native view.
    private static func normalizedLevel(magnitude: Float) -> Float {
        guard magnitude > 0 else { return 0 }
        let decibels = 20 * log10(magnitude)
        let level = (decibels - minDecibels) / (maxDecibels - minDecibels)
        let clampedLevel = min(1, max(0, level))
        return floor(clampedLevel * 255) / 255
    }

    /// In-place iterative radix-2 Cooley-Tukey FFT over `real`/`imaginary`.
    private func forwardTransform() {
        let count = Self.fftSize

        var reversed = 0
        for index in 1..<count {
            var bit = count >> 1
            while reversed & bit != 0 {
                reversed ^= bit
                bit >>= 1
            }
            reversed |= bit
            if index < reversed {
                real.swapAt(index, reversed)
                imaginary.swapAt(index, reversed)
            }
        }

        var length = 2
        while length <= count {
            let angle = -2 * Float.pi / Float(length)
            let stepReal = cos(angle)
            let stepImaginary = sin(angle)
            let half = length / 2
            for start in stride(from: 0, to: count, by: length) {
                var twiddleReal: Float = 1
                var twiddleImaginary: Float = 0
                for offset in 0..<half {
                    let low = start + offset
                    let high = low + half
                    let productReal = real[high] * twiddleReal - imaginary[high] * twiddleImaginary
                    let productImaginary = real[high] * twiddleImaginary + imaginary[high] * twiddleReal
                    real[high] = real[low] - productReal
                    imaginary[high] = imaginary[low] - productImaginary
                    real[low] += productReal
                    imaginary[low] += productImaginary
                    let nextTwiddleReal = twiddleReal * stepReal - twiddleImaginary * stepImaginary
                    twiddleImaginary = twiddleReal * stepImaginary + twiddleImaginary * stepReal
                    twiddleReal = nextTwiddleReal
                }
            }
            length <<= 1
        }
    }
}
