@preconcurrency import AVFoundation
import os

/// An audio buffer that moves between threads. The buffer is not changed after the tap hands it over.
struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

enum DictationError: Error, LocalizedError {
    case noMicrophone
    case speechUnavailable

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "No microphone input is available."
        case .speechUnavailable: "On-device speech recognition is not available for this language."
        }
    }
}

/// Reads the microphone with `AVAudioEngine`. Not tied to the main actor: the tap block runs on an
/// audio thread, so it must not inherit main actor isolation.
final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = OSAllocatedUnfairLock(initialState: false)

    /// Starts the microphone. Each buffer goes to `chunks`. `level` gets a 0...1 loudness per buffer.
    func start(
        into chunks: AsyncStream<AudioChunk>.Continuation,
        level: @escaping @Sendable (Float) -> Void
    ) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationError.noMicrophone }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            chunks.yield(AudioChunk(buffer: buffer))
            level(Self.loudness(of: buffer))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        lock.withLock { $0 = true }
    }

    func stop() {
        let wasRunning = lock.withLock { running -> Bool in
            defer { running = false }
            return running
        }
        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Loudness from 0 to 1. RMS in dB, with -50 dB as silence, and a curve that keeps quiet speech visible.
    static func loudness(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = max(0, min(1, (decibels + 50) / 50))
        return normalized.squareRoot()
    }
}

/// The latest mic level. The audio thread writes it; the main actor reads it on a timer.
final class LevelMeter: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: Float(0))

    var level: Float { value.withLock { $0 } }

    func update(_ level: Float) {
        value.withLock { $0 = level }
    }

    func reset() { update(0) }
}
