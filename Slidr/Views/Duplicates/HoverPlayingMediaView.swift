import SwiftUI
import AVFoundation
import AVKit

/// Self-contained media preview for the duplicate review UI.
/// Operates on a Sendable `MediaItemSnapshot` so the view can never touch a
/// tombstoned `@Model` after the user trashes the underlying item.
/// - Images: shows the cached thumbnail.
/// - GIFs: shows the thumbnail (no GIF auto-animation here — keeps things simple
///   alongside the video hover-play UX).
/// - Videos: thumbnail by default; on hover, swaps in a muted, looping AVPlayer.
struct HoverPlayingMediaView: View {
    let snapshot: MediaItemSnapshot
    @Environment(MediaLibrary.self) private var library

    @State private var isHovering = false
    @State private var player: AVPlayer?
    @State private var looperToken: NSObjectProtocol?

    var body: some View {
        ZStack {
            if snapshot.isVideo, isHovering, let player {
                AVPlayerLayerHost(player: player)
            } else {
                SnapshotThumbnailView(snapshot: snapshot)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            guard snapshot.isVideo else { return }
            if hovering {
                startVideo()
            } else {
                stopVideo()
            }
        }
        .onDisappear {
            stopVideo()
        }
    }

    private func startVideo() {
        let url = library.absoluteURL(for: snapshot)
        let p = AVPlayer(url: url)
        p.isMuted = true
        p.actionAtItemEnd = .none

        looperToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { _ in
            p.seek(to: .zero)
            p.play()
        }

        player = p
        p.play()
    }

    private func stopVideo() {
        if let token = looperToken {
            NotificationCenter.default.removeObserver(token)
            looperToken = nil
        }
        player?.pause()
        player = nil
    }
}

/// AsyncThumbnailImage equivalent that takes a Sendable snapshot.
/// Safe to render after the underlying `MediaItem` has been deleted.
struct SnapshotThumbnailView: View {
    let snapshot: MediaItemSnapshot
    @Environment(MediaLibrary.self) private var library
    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
            }
        }
        .task(id: snapshot.id) {
            isLoading = true
            image = try? await library.thumbnail(snapshot: snapshot, size: .large)
            isLoading = false
        }
    }
}

private struct AVPlayerLayerHost: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer as? AVPlayerLayer {
            layer.player = player
        }
    }
}
