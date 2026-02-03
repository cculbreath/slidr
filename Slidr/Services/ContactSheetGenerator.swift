import AVFoundation
import AppKit
import ImageIO
import OSLog

actor ContactSheetGenerator {
    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "ContactSheet")

    // MARK: - Video Frame Extraction

    func extractVideoFrames(from url: URL, count: Int, thumbnailSize: CGFloat) async throws -> [NSImage] {
        // Try AVFoundation first
        do {
            return try await extractVideoFramesAVF(from: url, count: count, thumbnailSize: thumbnailSize)
        } catch {
            Self.logger.warning("AVFoundation frame extraction failed for \(url.lastPathComponent): \(error.localizedDescription), trying ffmpeg")
        }

        // Fall back to ffmpeg
        let frames = await FFmpegHelper.extractFrames(from: url, count: count, thumbnailSize: thumbnailSize)
        if frames.isEmpty {
            Self.logger.error("ffmpeg frame extraction also returned 0 frames for \(url.lastPathComponent)")
        }
        return frames
    }

    private func extractVideoFramesAVF(from url: URL, count: Int, thumbnailSize: CGFloat) async throws -> [NSImage] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbnailSize, height: thumbnailSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let times: [CMTime] = (0..<count).map { i in
            let fraction = Double(i) / Double(max(count - 1, 1))
            return CMTime(seconds: fraction * durationSeconds, preferredTimescale: 600)
        }

        var frames: [NSImage] = []
        frames.reserveCapacity(count)

        for time in times {
            do {
                let (cgImage, _) = try await generator.image(at: time)
                frames.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
            } catch {
                // Retry with broader tolerance for problematic containers
                generator.requestedTimeToleranceBefore = CMTime(seconds: 2.0, preferredTimescale: 600)
                generator.requestedTimeToleranceAfter = CMTime(seconds: 2.0, preferredTimescale: 600)
                do {
                    let (cgImage, _) = try await generator.image(at: time)
                    frames.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                } catch {
                    Self.logger.debug("Frame extraction failed at \(CMTimeGetSeconds(time))s: \(error.localizedDescription)")
                }
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            }
        }

        return frames
    }

    // MARK: - GIF Frame Extraction

    func extractGIFFrames(from url: URL, count: Int) throws -> [NSImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ContactSheetError.failedToCreateImageSource
        }

        let totalFrames = CGImageSourceGetCount(source)
        guard totalFrames > 0 else { return [] }

        let step = max(totalFrames / count, 1)
        var frames: [NSImage] = []

        for i in stride(from: 0, to: totalFrames, by: step) {
            guard frames.count < count else { break }
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                frames.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
            }
        }

        return frames
    }

    // MARK: - Contact Sheet Composition

    func composeContactSheet(frames: [NSImage], columns: Int, thumbSize: CGFloat, jpegQuality: CGFloat) -> Data? {
        guard !frames.isEmpty else { return nil }

        let rows = Int(ceil(Double(frames.count) / Double(columns)))
        let totalWidth = CGFloat(columns) * thumbSize
        let totalHeight = CGFloat(rows) * thumbSize

        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(totalWidth),
            pixelsHigh: Int(totalHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let rep = bitmapRep else { return nil }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context

        context.imageInterpolation = .high

        for (index, frame) in frames.enumerated() {
            let col = index % columns
            let row = index / columns
            let x = CGFloat(col) * thumbSize
            let y = totalHeight - CGFloat(row + 1) * thumbSize // flip Y for AppKit

            let sourceSize = frame.size
            let scale = min(thumbSize / sourceSize.width, thumbSize / sourceSize.height)
            let drawWidth = sourceSize.width * scale
            let drawHeight = sourceSize.height * scale
            let drawX = x + (thumbSize - drawWidth) / 2
            let drawY = y + (thumbSize - drawHeight) / 2

            frame.draw(in: NSRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight))
        }

        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
    }

    // MARK: - Video Frame Range (Zoom)

    func extractVideoFrameRange(from url: URL, startFraction: Double, endFraction: Double, count: Int, thumbSize: CGFloat) async throws -> [NSImage] {
        // Try AVFoundation first
        do {
            return try await extractVideoFrameRangeAVF(from: url, startFraction: startFraction, endFraction: endFraction, count: count, thumbSize: thumbSize)
        } catch {
            Self.logger.warning("AVFoundation range extraction failed for \(url.lastPathComponent): \(error.localizedDescription), trying ffmpeg")
        }

        return await FFmpegHelper.extractFrameRange(from: url, startFraction: startFraction, endFraction: endFraction, count: count, thumbSize: thumbSize)
    }

    private func extractVideoFrameRangeAVF(from url: URL, startFraction: Double, endFraction: Double, count: Int, thumbSize: CGFloat) async throws -> [NSImage] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbSize, height: thumbSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)

        let startTime = startFraction * durationSeconds
        let endTime = endFraction * durationSeconds

        let times: [CMTime] = (0..<count).map { i in
            let fraction = Double(i) / Double(max(count - 1, 1))
            let time = startTime + fraction * (endTime - startTime)
            return CMTime(seconds: time, preferredTimescale: 600)
        }

        var frames: [NSImage] = []
        for time in times {
            do {
                let (cgImage, _) = try await generator.image(at: time)
                frames.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
            } catch {
                generator.requestedTimeToleranceBefore = CMTime(seconds: 2.0, preferredTimescale: 600)
                generator.requestedTimeToleranceAfter = CMTime(seconds: 2.0, preferredTimescale: 600)
                do {
                    let (cgImage, _) = try await generator.image(at: time)
                    frames.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                } catch {
                    Self.logger.debug("Range frame extraction failed: \(error.localizedDescription)")
                }
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
            }
        }

        return frames
    }

    // MARK: - Single Frame (Max Resolution)

    func extractSingleFrame(from url: URL, atFraction: Double, maxSize: CGFloat) async throws -> NSImage {
        // Try AVFoundation first
        do {
            return try await extractSingleFrameAVF(from: url, atFraction: atFraction, maxSize: maxSize)
        } catch {
            Self.logger.warning("AVFoundation single frame failed for \(url.lastPathComponent): \(error.localizedDescription), trying ffmpeg")
        }

        // Fall back to ffmpeg
        guard let duration = await FFmpegHelper.videoDuration(url: url) else {
            throw ContactSheetError.ffmpegExtractionFailed
        }
        let time = atFraction * duration
        guard let image = await FFmpegHelper.extractFrame(from: url, atSeconds: time, maxSize: maxSize) else {
            throw ContactSheetError.ffmpegExtractionFailed
        }
        return image
    }

    private func extractSingleFrameAVF(from url: URL, atFraction: Double, maxSize: CGFloat) async throws -> NSImage {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let time = CMTime(seconds: atFraction * durationSeconds, preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: time)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Static Image

    func loadStaticImage(from url: URL, maxSize: CGFloat) throws -> NSImage {
        guard let image = NSImage(contentsOf: url) else {
            throw ContactSheetError.failedToLoadImage
        }

        let size = image.size
        if size.width <= maxSize && size.height <= maxSize {
            return image
        }

        let scale = min(maxSize / size.width, maxSize / size.height)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()

        return resized
    }

    // MARK: - Convenience: Full Contact Sheet Pipeline

    func generateOverviewSheet(from url: URL, mediaType: MediaType, frameCount: Int = 20) async throws -> Data? {
        var frames: [NSImage]

        switch mediaType {
        case .video:
            frames = try await extractVideoFrames(from: url, count: frameCount, thumbnailSize: 160)
            if frames.isEmpty {
                Self.logger.error("All frame extraction methods failed for \(url.lastPathComponent)")
                return nil
            }
        case .gif:
            frames = try extractGIFFrames(from: url, count: frameCount)
        case .image:
            let image = try loadStaticImage(from: url, maxSize: 1200)
            return await MainActor.run { image.jpegData(quality: 0.9) }
        }

        return composeContactSheet(frames: frames, columns: 10, thumbSize: 160, jpegQuality: 0.8)
    }

    func generateZoomSheet(from url: URL, startFraction: Double, endFraction: Double) async throws -> Data? {
        let frames = try await extractVideoFrameRange(from: url, startFraction: startFraction, endFraction: endFraction, count: 6, thumbSize: 400)
        return composeContactSheet(frames: frames, columns: 3, thumbSize: 400, jpegQuality: 0.9)
    }

    func generateSingleFrameData(from url: URL, atFraction: Double) async throws -> Data? {
        let frame = try await extractSingleFrame(from: url, atFraction: atFraction, maxSize: 1200)
        return await MainActor.run { frame.jpegData(quality: 0.95) }
    }
}

// MARK: - Errors

enum ContactSheetError: LocalizedError {
    case failedToCreateImageSource
    case failedToLoadImage
    case ffmpegExtractionFailed

    var errorDescription: String? {
        switch self {
        case .failedToCreateImageSource:
            return "Failed to create image source for frame extraction"
        case .failedToLoadImage:
            return "Failed to load image file"
        case .ffmpegExtractionFailed:
            return "Failed to extract frame via ffmpeg"
        }
    }
}

// MARK: - NSImage JPEG Helper

private extension NSImage {
    func jpegData(quality: CGFloat) -> Data? {
        guard let tiffData = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
