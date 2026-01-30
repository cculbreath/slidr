import SwiftUI
import AppKit
import ImageIO

// MARK: - NSViewRepresentable (grid cell, slideshow, preview)

struct AnimatedGIFView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.canDrawSubviewsIntoLayer = true
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        context.coordinator.loadingTask?.cancel()

        context.coordinator.loadingTask = Task { @MainActor in
            let loadURL = url
            let data = try? await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: loadURL)
            }.value

            guard !Task.isCancelled, let data, let image = NSImage(data: data) else { return }
            nsView.image = image
            nsView.animates = true
        }
    }

    class Coordinator {
        var loadingTask: Task<Void, Never>?

        deinit {
            loadingTask?.cancel()
        }
    }
}

struct AsyncAnimatedGIFView: View {
    let item: MediaItem
    @Environment(MediaLibrary.self) private var library

    @State private var gifURL: URL?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let url = gifURL {
                AnimatedGIFView(url: url)
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            gifURL = library.absoluteURL(for: item)
            isLoading = false
        }
    }
}

// MARK: - Pure SwiftUI animated GIF (hover overlay)

struct GIFFrameView: View {
    let url: URL

    @State private var frames: [CGImage] = []
    @State private var frameDelays: [TimeInterval] = []
    @State private var totalDuration: TimeInterval = 0

    var body: some View {
        TimelineView(.animation) { context in
            if let frame = frameAt(date: context.date) {
                Image(decorative: frame, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .task {
            await loadGIF()
        }
    }

    private func frameAt(date: Date) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        guard frames.count > 1, totalDuration > 0 else { return frames.first }

        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: totalDuration)
        var accumulated: TimeInterval = 0
        for (i, delay) in frameDelays.enumerated() {
            accumulated += delay
            if elapsed < accumulated {
                return frames[i]
            }
        }
        return frames.last
    }

    private func loadGIF() async {
        let gifURL = url
        let result = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else {
                return (frames: [CGImage](), delays: [TimeInterval]())
            }
            let count = CGImageSourceGetCount(source)
            var loadedFrames: [CGImage] = []
            var delays: [TimeInterval] = []

            for i in 0..<count {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                loadedFrames.append(cgImage)

                let delay: TimeInterval
                if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                   let gifProps = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                    delay = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? TimeInterval
                        ?? gifProps[kCGImagePropertyGIFDelayTime as String] as? TimeInterval
                        ?? 0.1
                } else {
                    delay = 0.1
                }
                delays.append(max(delay, 0.02))
            }

            return (frames: loadedFrames, delays: delays)
        }.value

        guard !Task.isCancelled else { return }
        frames = result.frames
        frameDelays = result.delays
        totalDuration = result.delays.reduce(0, +)
    }
}
