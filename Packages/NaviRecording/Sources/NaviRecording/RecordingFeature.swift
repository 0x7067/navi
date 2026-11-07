import AppKit
import os

/// Screen recording: record bar, recorder, camera bubble, click and key overlays, GIF, and trim.
///
/// Flow: the app picks a region and calls `showRecordBar`. The user sets the options and picks
/// Record GIF or Record Video. A red item appears in the menu bar. Clicking it, or calling `stop()`,
/// ends the recording and calls `onFinish` with the file.
///
/// Files go to a temp folder (`NaviRecordings` in the temporary directory) as `Navi 2026-11-06 at 16.10.12.mp4`.
/// The app copies the result where it needs it, for example into the Inbox.
///
/// Permissions: Screen Recording for everything. Microphone and Camera when those options are on.
/// Input Monitoring for the keystroke overlay. `Info.plist` needs `NSCameraUsageDescription` and
/// `NSMicrophoneUsageDescription`, and the app needs the camera and audio input entitlements.
@MainActor
public final class RecordingFeature {
    private enum State {
        case idle
        /// The record bar is on screen.
        case choosing
        /// The user picked Record. The stream is starting.
        case starting
        case recording
        /// The stream stopped. The file is closing.
        case stopping
    }

    /// Called with a message when something goes wrong: a missing permission, a stream error,
    /// a failed GIF. Cancel does not call it.
    public var onError: ((any Error) -> Void)?

    private var state = State.idle
    private var bar: RecordBarController?
    private var onFinish: ((RecordingResult) -> Void)?
    private var wantsGIF = false
    private var stopRequestedWhileStarting = false

    private let recorder = ScreenRecorder()
    private let bubble = CameraBubble()
    private var overlay: InputOverlay?
    private var pill: StopPill?
    private let logger = Logger(subsystem: "com.donovanhiland.navi", category: "Recording")

    public init() {
        recorder.onUnexpectedStop = { [weak self] _ in self?.stop() }
    }

    /// True from the moment the user picks Record until the file is closed.
    public var isRecording: Bool { state == .starting || state == .recording }

    // MARK: Permission

    /// Screen Recording permission.
    public static var hasScreenAccess: Bool { CGPreflightScreenCaptureAccess() }

    // MARK: Record bar

    /// Shows the record bar for a region the app picked. Replaces a bar that is already open.
    /// While a recording runs or finishes, it reports `RecordingError.busy` and does nothing.
    ///
    /// - Parameter onFinish: called once with the finished file. It is not called on cancel (Esc).
    public func showRecordBar(region: RecordingRegion, onFinish: @escaping (RecordingResult) -> Void) {
        guard state == .idle || state == .choosing else {
            onError?(RecordingError.busy)
            return
        }
        guard Self.hasScreenAccess else {
            _ = CGRequestScreenCaptureAccess()
            onError?(RecordingError.noScreenAccess)
            return
        }
        closeBar()
        bubble.hide()
        guard let bar = RecordBarController(region: region, options: RecordingOptions()) else {
            onError?(RecordingError.noDisplay)
            return
        }
        self.bar = bar
        self.onFinish = onFinish
        state = .choosing

        bar.model.onCancel = { [weak self] in self?.cancelBar() }
        bar.model.onStart = { [weak self] format in self?.begin(format) }
        bar.model.onCameraChange = { [weak self] isOn in self?.cameraOptionChanged(isOn) }
        bar.show()
    }

    /// Stops the recording and calls `onFinish` when the file is ready.
    /// Called from the red menu bar item too. Does nothing when nothing is recording.
    public func stop() {
        switch state {
        case .starting:
            stopRequestedWhileStarting = true
        case .recording:
            finish()
        default:
            break
        }
    }

    // MARK: GIF and trim

    /// Converts an MP4 to a looping GIF next to it. About 15 fps, at most 800 points wide, no sound.
    public nonisolated static func makeGIF(from url: URL) async throws -> URL {
        try await GIFExporter.makeGIF(from: url)
    }

    /// Opens a trim window for a video. Returns the trimmed file, the same URL when nothing was cut,
    /// or nil when the user cancels or the file cannot be trimmed.
    public func trim(_ url: URL) async -> URL? {
        await TrimWindow.trim(url)
    }

    // MARK: Private: bar

    private func cancelBar() {
        guard state == .choosing else { return }
        closeBar()
        bubble.hide()
        onFinish = nil
        state = .idle
    }

    private func closeBar() {
        bar?.close()
        bar = nil
    }

    private func cameraOptionChanged(_ isOn: Bool) {
        guard let bar else { return }
        guard isOn else {
            bubble.hide()
            return
        }
        guard let region = bar.model.cocoaFrame else { return }
        Task {
            let shown = await bubble.show(inside: region)
            guard shown else {
                bar.model.options.camera = false
                return
            }
            // The user may have switched it off or cancelled while the camera started.
            let stillWanted = state == .starting || state == .recording
                || (state == .choosing && self.bar?.model.options.camera == true)
            if !stillWanted { bubble.hide() }
        }
    }

    // MARK: Private: start

    private func begin(_ format: RecordingFormat) {
        guard state == .choosing, let bar else { return }
        let region = bar.model.region
        var options = bar.model.options
        let frame = bar.model.cocoaFrame ?? .zero
        let excluded = bar.windowIDs
        closeBar()
        state = .starting
        wantsGIF = format == .gif
        stopRequestedWhileStarting = false
        // A GIF has no sound.
        if wantsGIF {
            options.microphone = false
            options.computerAudio = false
        }

        let stopAction: @MainActor () -> Void = { [weak self] in self?.stop() }
        Task {
            do {
                if options.microphone, !(await Permissions.microphone()) { options.microphone = false }

                let overlay = InputOverlay(keyPillArea: frame)
                self.overlay = overlay
                overlay.start(clicks: options.showClicks, keystrokes: options.showKeystrokes)

                let pill = StopPill(onClick: stopAction)
                self.pill = pill
                var excludedIDs = excluded
                if let id = pill.windowID { excludedIDs.insert(id) }

                try await recorder.start(ScreenRecorder.Settings(
                    region: region, options: options, outputURL: try Self.newFileURL(),
                    excludedWindowIDs: excludedIDs, recordsAudio: !wantsGIF
                ))
                state = .recording
                pill.startTimer()
                if stopRequestedWhileStarting { finish() }
            } catch {
                logger.error("Could not start: \(error.localizedDescription)")
                teardownOverlays()
                state = .idle
                onFinish = nil
                onError?(error)
            }
        }
    }

    // MARK: Private: finish

    private func finish() {
        guard state == .recording else { return }
        state = .stopping
        teardownOverlays()
        let isGIF = wantsGIF
        let onFinish = self.onFinish
        self.onFinish = nil

        Task {
            do {
                let output = try await recorder.stop()
                var result = RecordingResult(url: output.url, isGIF: false, videoURL: output.url, duration: output.duration)
                if isGIF {
                    let gif = try await Self.makeGIF(from: output.url)
                    result = RecordingResult(url: gif, isGIF: true, videoURL: output.url, duration: output.duration)
                }
                state = .idle
                onFinish?(result)
            } catch {
                logger.error("Could not finish: \(error.localizedDescription)")
                state = .idle
                onError?(error)
            }
        }
    }

    private func teardownOverlays() {
        pill?.remove()
        pill = nil
        overlay?.stop()
        overlay = nil
        bubble.hide()
    }

    private static func newFileURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NaviRecordings", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: RecordingMath.fileName(for: Date(), fileExtension: "mp4"))
    }
}
