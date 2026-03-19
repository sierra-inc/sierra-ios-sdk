// Copyright Sierra

import AVFoundation
import Foundation

/// Manages buffered playback of server-provided audio chunks.
///
/// Responsibilities include:
/// - queueing decoded audio payloads for ordered playback
/// - converting and scheduling buffers on `AVAudioPlayerNode`
/// - reporting speaking lifecycle edges (started/stopped)
/// - emitting playback mark callbacks after buffer completion
final class AudioPlaybackQueue {
    var onPlaybackMark: ((String) -> Void)?
    var onDidStartSpeaking: (() -> Void)?
    var onDidStopSpeaking: (() -> Void)?

    private struct QueuedAudioBuffer {
        let data: Data
        let mark: String?
    }

    private let sampleRate: Double
    private let audioQueue = DispatchQueue(label: "com.sierra.sdk.voice.audioQueue")

    private var playerNode: AVAudioPlayerNode?
    private var audioBufferQueue: [QueuedAudioBuffer] = []
    private var isPlaying = false
    private var isSpeakingNotified = false

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func configure(playerNode: AVAudioPlayerNode) {
        self.playerNode = playerNode
    }

    func enqueue(_ audioData: Data, mark: String?) {
        audioQueue.async {
            self.audioBufferQueue.append(QueuedAudioBuffer(data: audioData, mark: mark))
            if !self.isPlaying {
                self.isPlaying = true
                self.setSpeakingNotified(true)
                self.playNextBuffer()
            }
        }
    }

    func clear() {
        audioQueue.async {
            self.audioBufferQueue.removeAll()
            self.isPlaying = false
            self.setSpeakingNotified(false)
            DispatchQueue.main.async {
                self.playerNode?.stop()
                self.playerNode?.play()
            }
        }
    }

    func stop() {
        audioQueue.sync {
            audioBufferQueue.removeAll()
            isPlaying = false
            setSpeakingNotified(false)
        }
        playerNode?.stop()
        playerNode = nil
    }

    private func playNextBuffer() {
        audioQueue.async {
            guard !self.audioBufferQueue.isEmpty, let player = self.playerNode else {
                self.isPlaying = false
                self.setSpeakingNotified(false)
                return
            }

            let queued = self.audioBufferQueue.removeFirst()
            guard let pcmBuffer = self.makePCMBuffer(from: queued.data) else {
                self.playNextBuffer()
                return
            }

            player.scheduleBuffer(pcmBuffer, completionHandler: { [weak self] in
                guard let self else { return }
                if let mark = queued.mark, !mark.isEmpty {
                    self.onPlaybackMark?(mark)
                }
                self.playNextBuffer()
            })
        }
    }

    private func setSpeakingNotified(_ isSpeaking: Bool) {
        guard isSpeakingNotified != isSpeaking else { return }
        isSpeakingNotified = isSpeaking
        DispatchQueue.main.async {
            if isSpeaking {
                self.onDidStartSpeaking?()
            } else {
                self.onDidStopSpeaking?()
            }
        }
    }

    private func makePCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(data.count / 2)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return nil
        }

        pcmBuffer.frameLength = frameCount
        data.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.bindMemory(to: Int16.self).baseAddress,
                  let dst = pcmBuffer.floatChannelData?.pointee else {
                return
            }
            for i in 0..<Int(frameCount) {
                dst[i] = Float(src[i]) / 32768.0
            }
        }
        return pcmBuffer
    }
}
