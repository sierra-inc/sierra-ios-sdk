// Copyright Sierra

import AVFoundation

enum AudioLevelMeter {
    static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sumOfSquares: Float = 0
        for i in 0..<count {
            sumOfSquares += samples[i] * samples[i]
        }
        return sqrtf(sumOfSquares / Float(count))
    }
}
