import SwiftUI
import AppKit

struct AnimatedGIFView: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.canDrawSubviewsIntoLayer = true
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if let data = try? Data(contentsOf: url),
           let image = NSImage(data: data) {
            nsView.image = image
            nsView.animates = true
        }
    }
}

struct AsyncAnimatedGIFView: View {
    let item: MediaItem
    let size: CGSize
    @Environment(MediaLibrary.self) private var library

    @State private var gifURL: URL?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let url = gifURL {
                AnimatedGIFView(url: url, size: size)
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .task {
            gifURL = library.absoluteURL(for: item)
            isLoading = false
        }
    }
}
