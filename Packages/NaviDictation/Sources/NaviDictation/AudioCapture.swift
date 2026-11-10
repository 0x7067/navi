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

/// The newest audio, up to `capacity` frames. Older chunks fall off the front. Pure, so it can be tested.
struct PreRollBuffer<Chunk> {
    let capacity: Int
    private(set) var chunks: [(chunk: Chunk, frames: Int)] = []
    private(set) var frames = 0

    init(capacity: Int) {
        self.capacity = capacity
    }

    mutating func append(_ chunk: Chunk, frames count: Int) {
        chunks.append((chunk, count))
        frames += count
        // Drop whole chunks from the front while the rest still covers the capacity.
        while let first = chunks.first, frames - first.frames >= capacity {
            frames -= first.frames
            chunks.removeFirst()
        }
    }

    /// Hands back the kept chunks, oldest first, and empties the buffer.
    mutating func drain() -> [Chunk] {
        defer {
            chunks = []
            frames = 0
        }
        return chunks.map(\.chunk)
    }
}

/// The microphone, in two modes.
///
/// - **Warm (default, like Wispr Flow):** the engine and its tap are set up ahead of time (`prepare`) but
///   not running, so there is no microphone indicator. A press only starts it (`open`), which is quick;
///   after the dictation it stops but stays set up (`pause`).
/// - **Keep ready (Hex's mode):** the stream stays open between dictations and keeps the last `preRoll`
///   seconds, so a press records from just before it. macOS shows the microphone indicator the whole time.
///
/// Not tied to the main actor: the tap block runs on an audio thread.
final class Microphone: @unchecked Sendable {
    /// Audio kept from before the press (Hex keeps 450 ms).
    static let preRoll: Double = 0.45
    /// Audio kept after the release, so the last word is not cut (Hex's `POST_RELEASE_TAIL`).
    static let releaseTail: Duration = .milliseconds(200)

    /// Holds audio buffers, which only move under the lock.
    private struct State: @unchecked Sendable {
        var running = false
        var prepared = false
        var sink: AsyncStream<AudioChunk>.Continuation?
        var preRoll = PreRollBuffer<AVAudioPCMBuffer>(capacity: 0)
        var level: Float = 0
    }

    private let engine = AVAudioEngine()
    /// Setup, start, stop, and teardown take turns (they run on different threads).
    private let setup = NSRecursiveLock()
    private let state = OSAllocatedUnfairLock(initialState: State())
    private static let logger = Logger(subsystem: "com.donovanhiland.navi", category: "Microphone")
    private var configurationObserver: (any NSObjectProtocol)?

    init() {
        // A new input device (AirPods, a USB mic) stops the engine. Open it again on the new device.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            let (wasRunning, wasPrepared) = state.withLock { ($0.running, $0.prepared) }
            guard wasPrepared else { return }
            Self.logger.info("Input device changed; setting up the microphone again")
            close()
            if wasRunning { try? open() } else { try? prepare() }
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    var isRunning: Bool { state.withLock { $0.running } }

    /// Loudness of the newest buffer, 0...1.
    var level: Float { state.withLock { $0.level } }

    /// Sets up the engine and its tap without starting the microphone (no indicator). Makes `open` quick.
    /// Can take a moment, so call it off the main thread.
    func prepare() throws {
        setup.lock()
        defer { setup.unlock() }
        guard !state.withLock({ $0.prepared }) else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationError.noMicrophone }
        let capacity = Int(format.sampleRate * Self.preRoll)
        state.withLock { $0.preRoll = PreRollBuffer(capacity: capacity) }
        // A small buffer (about 20 ms at 48 kHz) keeps the press and release boundaries tight.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.receive(buffer)
        }
        engine.prepare()
        state.withLock { $0.prepared = true }
    }

    /// Starts the microphone, setting it up first if needed.
    func open() throws {
        setup.lock()
        defer { setup.unlock() }
        guard !isRunning else { return }
        try prepare()
        try engine.start()
        state.withLock { $0.running = true }
    }

    /// Stops the microphone but keeps it set up, so the next `open` is quick. A capture still open ends.
    func pause() {
        setup.lock()
        defer { setup.unlock() }
        let (wasRunning, sink) = state.withLock { state -> (Bool, AsyncStream<AudioChunk>.Continuation?) in
            defer {
                state.running = false
                state.sink = nil
                state.level = 0
                _ = state.preRoll.drain()
            }
            return (state.running, state.sink)
        }
        sink?.finish()
        guard wasRunning else { return }
        engine.stop()
        engine.prepare()
    }

    /// Stops the microphone and takes the setup down.
    func close() {
        setup.lock()
        defer { setup.unlock() }
        pause()
        let wasPrepared = state.withLock { state -> Bool in
            defer { state.prepared = false }
            return state.prepared
        }
        guard wasPrepared else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()
    }

    /// Sends the audio to `sink` from now on. With `includePreRoll`, the kept audio from just before
    /// goes first.
    func beginCapture(into sink: AsyncStream<AudioChunk>.Continuation, includePreRoll: Bool) {
        let kept = state.withLockUnchecked { state -> [AVAudioPCMBuffer] in
            state.sink = sink
            let kept = state.preRoll.drain()
            return includePreRoll ? kept : []
        }
        for buffer in kept { sink.yield(AudioChunk(buffer: buffer)) }
    }

    /// Ends the capture: the sink gets no more audio and finishes.
    func endCapture() {
        let sink = state.withLock { state -> AsyncStream<AudioChunk>.Continuation? in
            defer { state.sink = nil }
            return state.sink
        }
        sink?.finish()
    }

    private func receive(_ buffer: AVAudioPCMBuffer) {
        let level = Self.loudness(of: buffer)
        let sink = state.withLock { state -> AsyncStream<AudioChunk>.Continuation? in
            state.level = level
            return state.sink
        }
        if let sink {
            sink.yield(AudioChunk(buffer: buffer))
        } else if let copy = Self.copy(buffer) {
            // The engine may reuse its buffer, so the pre-roll keeps a copy.
            state.withLock { $0.preRoll.append(copy, frames: Int(copy.frameLength)) }
        }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0 ..< min(source.count, target.count) {
            guard let from = source[index].mData, let to = target[index].mData else { continue }
            memcpy(to, from, Int(buffer.frameLength) * bytesPerFrame)
        }
        return copy
    }

    /// Loudness from 0 to 1. RMS in dB, with -50 dB as silence, and a curve that keeps quiet speech visible.
    static func loudness(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0 ..< Int(buffer.frameLength) {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = max(0, min(1, (decibels + 50) / 50))
        return normalized.squareRoot()
    }
}
