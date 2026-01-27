import ImageIO
import AppKit

struct GIFDecoder {
    struct Frame {
        let image: NSImage
        let duration: TimeInterval
    }

    struct GIFInfo {
        let frames: [Frame]
        let loopCount: Int
        let totalDuration: TimeInterval
        let size: CGSize
    }

    static func decode(url: URL) -> GIFInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }

        var frames: [Frame] = []
        var totalDuration: TimeInterval = 0
        var gifSize: CGSize = .zero

        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                continue
            }

            let duration = frameDuration(for: source, at: i)
            totalDuration += duration

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            frames.append(Frame(image: nsImage, duration: duration))

            if gifSize == .zero {
                gifSize = CGSize(width: cgImage.width, height: cgImage.height)
            }
        }

        let loopCount = GIFDecoder.loopCount(for: source)

        return GIFInfo(
            frames: frames,
            loopCount: loopCount,
            totalDuration: totalDuration,
            size: gifSize
        )
    }

    private static func frameDuration(for source: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }

        if let unclampedDelay = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclampedDelay > 0 {
            return unclampedDelay
        }

        if let delay = gifDict[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
            return delay
        }

        return 0.1
    }

    private static func loopCount(for source: CGImageSource) -> Int {
        guard let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
              let count = gifDict[kCGImagePropertyGIFLoopCount] as? Int else {
            return 0
        }
        return count
    }

    static func firstFrame(url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    static func metadata(url: URL) -> (frameCount: Int, duration: TimeInterval, size: CGSize)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }

        var totalDuration: TimeInterval = 0
        for i in 0..<frameCount {
            totalDuration += frameDuration(for: source, at: i)
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let size = CGSize(width: cgImage.width, height: cgImage.height)

        return (frameCount, totalDuration, size)
    }
}
