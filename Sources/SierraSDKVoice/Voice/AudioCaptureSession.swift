// Copyright Sierra

import AVFoundation
import Foundation
import SierraSDK

/// Manages microphone capture and upstream audio preprocessing.
///
/// Responsibilities include:
/// - owning the input tap lifecycle on `AVAudioInputNode`
/// - converting captured frames into the linear16 transport format
/// - enforcing pause/mute capture policy for voice interaction states
/// - applying adaptive echo-gate filtering while agent speech is active
final class AudioCaptureSession {
    private struct CaptureStateSnapshot {
        let isInterruptionPaused: Bool
        let isUserMuted: Bool
        let isSpeakingMuted: Bool
        let isSpeakingState: Bool
    }

    /// How the capture tap treats one buffer while audio capture is being suppressed.
    enum CapturePolicy: Equatable {
        /// Emit nothing (audio-session interruption: the session is suspended, timeline frozen).
        case drop
        /// Emit equal-length silence (user mute / speaking-mute: the call timeline keeps advancing).
        case silence
        /// Forward captured audio through the normal (echo-gated) path.
        case send
    }

    var onAudioData: ((Data) -> Void)?

    /// Emits the input RMS level from the audio tap thread, and zero from pause transitions.
    /// Callers must dispatch to their target queue before touching thread-confined state.
    var onInputLevel: ((Float) -> Void)?

    /// Bytes per sample for the mono linear16 (signed 16-bit) transport format.
    private static let linear16BytesPerSample = 2

    /// Byte length of `frameCount` mono linear16 samples. Single source of truth shared by the
    /// converted-audio emit path and the echo-gate silence path so both stay equal-length.
    static func linear16ByteCount(frameCount: AVAudioFrameCount) -> Int {
        Int(frameCount) * linear16BytesPerSample
    }

    /// Decides how a captured buffer is handled while capture is suppressed. Interruption wins and
    /// drops, because the OS deactivated the audio session and the server's byte-counted AudioIn
    /// clock is not advancing; user mute and speaking-mute emit equal-length silence so that clock
    /// keeps advancing and agent audio stays aligned during playback. See CH-633.
    static func capturePolicy(interruptionPaused: Bool, userMuted: Bool, speakingMuted: Bool) -> CapturePolicy {
        if interruptionPaused {
            return .drop
        }
        if userMuted || speakingMuted {
            return .silence
        }
        return .send
    }

    private let disableInterruptions: Bool
    private let sampleRate: Double
    private let inputTapDuration: Double

    // Adaptive echo gate state -- accessed from the AVAudioEngine tap thread.
    private let echoGateFloorMultiplier: Float = 2.2
    private let echoGateFloorDecay: Float = 0.985
    private let echoGateMinThreshold: Float = 0.012
    private let echoGateOnsetFrames: Int = 2
    private let echoGateOffsetFrames: Int = 4
    private let echoGateInitialFloorRMS: Float = 0.01
    private var echoGateFloorRMS: Float = 0.01
    private var echoGateAboveCount: Int = 0
    private var echoGateBelowCount: Int = 0
    private var echoGatePassing: Bool = false

    private let listeningPauseQueue = DispatchQueue(
        label: "com.sierra.sdk.voice.listeningpause",
        attributes: .concurrent
    )
    private var _isListeningPaused = false
    private var _isSpeakingMuted = false
    private var _isInterruptionPaused = false
    private var _isSpeakingState = false

    private var inputNode: AVAudioInputNode?
    private var converter: AVAudioConverter?
    private var isRunning = false
    // Accessed only from the audio tap callback thread.
    private var lastTapSpeakingState = false

    init(disableInterruptions: Bool, sampleRate: Double, inputTapDuration: Double) {
        self.disableInterruptions = disableInterruptions
        self.sampleRate = sampleRate
        self.inputTapDuration = inputTapDuration
    }

    func start(inputNode: AVAudioInputNode, inputFormat: AVAudioFormat) {
        self.inputNode = inputNode
        self.isRunning = true

        let convertFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )!
        let converter = AVAudioConverter(from: inputFormat, to: convertFormat)
        self.converter = converter

        let inputTapBufferSize = AVAudioFrameCount(
            max(240, Int(inputFormat.sampleRate * inputTapDuration))
        )
        inputNode.installTap(
            onBus: 0,
            bufferSize: inputTapBufferSize,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            let stateSnapshot = self.captureStateSnapshot()
            guard self.isRunning else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate
            )

            let policy = Self.capturePolicy(
                interruptionPaused: stateSnapshot.isInterruptionPaused,
                userMuted: stateSnapshot.isUserMuted,
                speakingMuted: stateSnapshot.isSpeakingMuted
            )
            if policy == .drop {
                // Audio-session interruption: the session is suspended, so emit nothing (status quo).
                self.onInputLevel?(0)
                return
            }

            // Decide whether this buffer is transmitted as captured audio or replaced by silence.
            // Both outcomes are sized from the converter's actual output below, so substituted
            // silence is exactly as long as the audio it replaces and the server's byte-counted
            // AudioIn clock stays aligned. See CH-633.
            let emitSilence: Bool
            if policy == .silence {
                // User mute or speaking-mute: keep the timeline advancing with silence. The real mic
                // bytes are never transmitted while muted.
                self.resetEchoGateState()
                self.lastTapSpeakingState = stateSnapshot.isSpeakingState
                self.onInputLevel?(0)
                emitSilence = true
            } else {
                if stateSnapshot.isSpeakingState != self.lastTapSpeakingState {
                    // Keep echo gate state aligned with speaking-state edges.
                    self.resetEchoGateState()
                    self.lastTapSpeakingState = stateSnapshot.isSpeakingState
                }

                let rms = AudioLevelMeter.computeRMS(buffer: buffer)

                if stateSnapshot.isSpeakingState && !self.disableInterruptions {
                    // A closed echo gate means these frames are agent echo, not user speech; replace
                    // them with silence rather than dropping so the timeline keeps its true duration.
                    emitSilence = !self.shouldPassSpeakingGate(rms: rms)
                } else {
                    self.resetEchoGateState()
                    emitSilence = false
                }
                self.onInputLevel?(emitSilence ? 0 : rms)
            }

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: convertFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if let error {
                debugLog("Audio conversion error: \(error)")
                return
            }

            // Size both the silence and the captured payload from the converter's actual output so
            // they are always identical length.
            let byteCount = Self.linear16ByteCount(frameCount: convertedBuffer.frameLength)
            if emitSilence {
                self.onAudioData?(Data(count: byteCount))
            } else if let channelData = convertedBuffer.int16ChannelData {
                self.onAudioData?(Data(bytes: channelData[0], count: byteCount))
            }
        }
    }

    func stop() {
        isRunning = false
        inputNode?.removeTap(onBus: 0)
        inputNode = nil
        converter = nil
        lastTapSpeakingState = false
    }

    func pauseListening() {
        updatePauseState {
            _isListeningPaused = true
            debugLog("SVP listening paused (user mute/pause). speakingMuted=\(_isSpeakingMuted)")
        }
    }

    func resumeListening() {
        listeningPauseQueue.sync(flags: .barrier) {
            _isListeningPaused = false
            debugLog("SVP listening resumed. speakingMuted=\(_isSpeakingMuted)")
        }
    }

    /// Suppress capture for an audio-session interruption (e.g. an incoming phone call). Unlike
    /// user mute, this drops audio rather than emitting silence, because the OS has deactivated the
    /// session and its timeline is not advancing. Distinct from `pauseListening()` so the two can
    /// be told apart at the tap. See CH-633.
    func pauseForInterruption() {
        listeningPauseQueue.sync(flags: .barrier) {
            _isInterruptionPaused = true
            debugLog("SVP capture paused for audio-session interruption.")
        }
        onInputLevel?(0)
    }

    func resumeFromInterruption() {
        listeningPauseQueue.sync(flags: .barrier) {
            _isInterruptionPaused = false
            debugLog("SVP capture resumed after audio-session interruption.")
        }
    }

    func setSpeakingState(_ isSpeaking: Bool) {
        listeningPauseQueue.sync(flags: .barrier) {
            self._isSpeakingState = isSpeaking
        }
    }

    func setSpeakingMuted(_ muted: Bool, stateDescription: String) {
        updatePauseState {
            guard _isSpeakingMuted != muted else { return }
            _isSpeakingMuted = muted
            debugLog("SVP speaking-mute \(muted ? "enabled" : "disabled") for state=\(stateDescription)")
        }
    }

    func resetListeningPauseState() {
        listeningPauseQueue.sync(flags: .barrier) {
            _isListeningPaused = false
            _isSpeakingMuted = false
            _isInterruptionPaused = false
            _isSpeakingState = false
        }
    }

    private func captureStateSnapshot() -> CaptureStateSnapshot {
        listeningPauseQueue.sync {
            CaptureStateSnapshot(
                isInterruptionPaused: _isInterruptionPaused,
                isUserMuted: _isListeningPaused,
                isSpeakingMuted: _isSpeakingMuted,
                isSpeakingState: _isSpeakingState
            )
        }
    }

    private func updatePauseState(_ update: () -> Void) {
        var wasPaused = false
        var isPaused = false
        listeningPauseQueue.sync(flags: .barrier) {
            wasPaused = _isListeningPaused || _isSpeakingMuted
            update()
            isPaused = _isListeningPaused || _isSpeakingMuted
        }
        if !wasPaused, isPaused {
            onInputLevel?(0)
        }
    }

    private func shouldPassSpeakingGate(rms: Float) -> Bool {
        let adaptiveThreshold = max(echoGateMinThreshold, echoGateFloorRMS * echoGateFloorMultiplier)

        if !echoGatePassing {
            echoGateFloorRMS = echoGateFloorDecay * echoGateFloorRMS + (1 - echoGateFloorDecay) * rms
        }

        if rms >= adaptiveThreshold {
            echoGateAboveCount += 1
            echoGateBelowCount = 0
            if echoGateAboveCount >= echoGateOnsetFrames {
                echoGatePassing = true
            }
        } else {
            echoGateAboveCount = 0
            echoGateBelowCount += 1
            if echoGateBelowCount >= echoGateOffsetFrames {
                echoGatePassing = false
            }
        }

        return echoGatePassing
    }

    private func resetEchoGateState() {
        echoGatePassing = false
        echoGateAboveCount = 0
        echoGateBelowCount = 0
        echoGateFloorRMS = echoGateInitialFloorRMS
    }
}
