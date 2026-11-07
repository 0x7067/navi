import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Converts an MP4 to a looping GIF with ImageIO. The GIF has no sound.
enum GIFExporter {
    /// Writes `<name>.gif` next to the video and returns its URL.
    /// About 15 frames per second, at most 800 pixels wide.
    static func makeGIF(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingError.gifFailed("the file has no video")
        }
        let naturalSize = try await track.load(.naturalSize)
        let plan = RecordingMath.gifPlan(duration: duration, naturalSize: naturalSize)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: plan.width, height: plan.height)
        // A little slack is much faster than exact frames, and a frame is 1/15 s anyway.
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)

        let outputURL = videoURL.deletingPathExtension().appendingPathExtension("gif")
        try? FileManager.default.removeItem(at: outputURL)
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL, UTType.gif.identifier as CFString, plan.times.count, nil
        ) else { throw RecordingError.gifFailed("could not create the file") }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: plan.frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: plan.frameDelay,
            ]
        ] as CFDictionary

        let times = plan.times.map { CMTime(seconds: $0, preferredTimescale: 600) }
        var added = 0
        var previous: CGImage?
        for await result in generator.images(for: times) {
            // A frame that fails repeats the one before it, so the timing stays right.
            let image = (try? result.image) ?? previous
            guard let image else { continue }
            CGImageDestinationAddImage(destination, image, frameProperties)
            previous = image
            added += 1
        }
        // Finalize needs exactly the announced count.
        while added < plan.times.count, let previous {
            CGImageDestinationAddImage(destination, previous, frameProperties)
            added += 1
        }
        guard added > 0, CGImageDestinationFinalize(destination) else {
            throw RecordingError.gifFailed("no frames could be read")
        }
        return outputURL
    }
}
