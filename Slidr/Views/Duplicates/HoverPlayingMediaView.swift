import SwiftUI
import AVFoundation
import AVKit

/// Self-contained media preview for the duplicate review UI.
/// Operates on a Sendable `MediaItemSnapshot` so the view can never touch a
/// tombstoned `@Model` after the user trashes the underlying item.
/// - Videos: thumbnail by default; on hover, swaps in a muted, looping AVPlayer.
/// - Everything else: shows the cached thumbnail.
struct HoverPlayingMediaView: View {
    let snapshot: MediaItemSnapshot
    @Environment(MediaLibrary.self) private var library

    @State private var isHovering = false
    @State private var player: AVPlayer?
    @State private var looperToken: NSObjectProtocol?

    var body: some View {
        ZStack {
            if snapshot.isVideo, isHovering, let player {
                AVPlayerLayerView(player: player, videoGravity: .resizeAspect)
            } else {
                AsyncThumbnailImage(snapshot: snapshot, size: .large)
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
