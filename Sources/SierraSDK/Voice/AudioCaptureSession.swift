// Copyright Sierra

import AVFoundation
import Foundation

/// Manages microphone capture and upstream audio preprocessing.
///
/// Responsibilities include:
/// - owning the input tap lifecycle on `AVAudioInputNode`
/// - converting captured frames into the linear16 transport format
/// - enforcing pause/mute capture policy for voice interaction states
/// - applying adaptive echo-gate filtering while agent speech is active
final class AudioCaptureSession {
    private struct CaptureStateSnapshot {
        let isListeningPaused: Bool
        let isSpeakingState: Bool
    }

    var onAudioData: ((Data) -> Void)?

    private let disableInterruptions: Bool
    private let sampleRate: Double
    private let inputTapDuration: Double

    // Adaptive echo gate state -- accessed from the AVAudioEngine tap thread.
    private let echoGateFloorMultiplier: Float = 2.5
    private let echoGateFloorDecay: Float = 0.985
    private let echoGateMinThreshold: Float = 0.015
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
            guard self.isRunning, !stateSnapshot.isListeningPaused else { return }

            if stateSnapshot.isSpeakingState != self.lastTapSpeakingState {
                // Keep echo gate state aligned with speaking-state edges.
                self.resetEchoGateState()
                self.lastTapSpeakingState = stateSnapshot.isSpeakingState
            }

            if stateSnapshot.isSpeakingState && !self.disableInterruptions {
                guard let samples = buffer.floatChannelData?[0] else { return }
                let count = Int(buffer.frameLength)
                var sumOfSquares: Float = 0
                for i in 0..<count {
                    sumOfSquares += samples[i] * samples[i]
                }
                let rms = sqrtf(sumOfSquares / Float(count))
                if !self.shouldPassSpeakingGate(rms: rms) {
                    return
                }
            } else {
                self.resetEchoGateState()
            }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate
            )
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

            if let channelData = convertedBuffer.int16ChannelData {
                let data = Data(
                    bytes: channelData[0],
                    count: Int(convertedBuffer.frameLength) * 2
                )
                self.onAudioData?(data)
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
        listeningPauseQueue.sync(flags: .barrier) {
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

    func setSpeakingState(_ isSpeaking: Bool) {
        listeningPauseQueue.sync(flags: .barrier) {
            self._isSpeakingState = isSpeaking
        }
    }

    func setSpeakingMuted(_ muted: Bool, stateDescription: String) {
        listeningPauseQueue.sync(flags: .barrier) {
            guard _isSpeakingMuted != muted else { return }
            _isSpeakingMuted = muted
            debugLog("SVP speaking-mute \(muted ? "enabled" : "disabled") for state=\(stateDescription)")
        }
    }

    func resetListeningPauseState() {
        listeningPauseQueue.sync(flags: .barrier) {
            _isListeningPaused = false
            _isSpeakingMuted = false
            _isSpeakingState = false
        }
    }

    private func captureStateSnapshot() -> CaptureStateSnapshot {
        listeningPauseQueue.sync {
            CaptureStateSnapshot(
                isListeningPaused: _isListeningPaused || _isSpeakingMuted,
                isSpeakingState: _isSpeakingState
            )
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
