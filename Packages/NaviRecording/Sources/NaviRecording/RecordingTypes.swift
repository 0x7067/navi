import CoreGraphics
import Foundation

/// What to record. The app picks the region with its own overlay and passes it in.
public enum RecordingRegion: Sendable, Equatable {
    /// A whole display.
    case display(CGDirectDisplayID)
    /// A rectangle of a display, in display-local points. The origin is the top left corner.
    case area(CGDirectDisplayID, CGRect)
    /// One window alone. Nothing behind it gets in, and Navi's camera and overlays do not show.
    case window(CGWindowID)
}

/// A finished recording.
public struct RecordingResult: Sendable, Equatable {
    /// The file to use: the GIF when `isGIF` is true, otherwise the MP4.
    public let url: URL
    public let isGIF: Bool
    /// The MP4 the recording was made as. For a video result it equals `url`.
    /// Keep it to offer an MP4 or GIF switch, or to trim.
    public let videoURL: URL
    /// Length in seconds.
    public let duration: TimeInterval

    public init(url: URL, isGIF: Bool, videoURL: URL, duration: TimeInterval) {
        self.url = url
        self.isGIF = isGIF
        self.videoURL = videoURL
        self.duration = duration
    }
}

/// The choices in the record bar.
public struct RecordingOptions: Sendable, Equatable {
    public var framesPerSecond: Int = 30
    public var microphone = false
    public var computerAudio = false
    public var camera = false
    public var showClicks = true
    public var showKeystrokes = false
    public var hideDesktopIcons = false
    public var muteNotifications = false

    public init() {}
}

public enum RecordingError: Error, Sendable, LocalizedError {
    case noScreenAccess
    case busy
    case noDisplay
    case noWindow
    case noFrames
    case writerFailed(String)
    case gifFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noScreenAccess: "Navi needs Screen Recording permission."
        case .busy: "Navi is still finishing the last recording."
        case .noDisplay: "The display is not available."
        case .noWindow: "The window is not available."
        case .noFrames: "The recording has no video frames."
        case .writerFailed(let reason): "Writing the video failed: \(reason)"
        case .gifFailed(let reason): "Making the GIF failed: \(reason)"
        }
    }
}
