import SwiftUI
import SwiftData

struct MediaThumbnailView: View {
    let item: MediaItem
    let size: ThumbnailSize
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @Query private var settingsQuery: [AppSettings]
    @State private var isHovering = false
    @State private var hoverLocation: CGPoint = .zero
    @State private var hoverPosition: CGFloat = 0.5

    private var settings: AppSettings? {
        settingsQuery.first
    }

    private var animateGIFs: Bool {
        settings?.animateGIFsInGrid ?? false
    }

    private var showFilenames: Bool {
        settings?.gridShowFilenames ?? false
    }

    var body: some View {
        VStack(spacing: 4) {
            thumbnailContent
                .frame(width: size.pixelSize, height: size.pixelSize)

            if showFilenames {
                Text(item.originalFilename)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(width: size.pixelSize)
            }
        }
    }

    private var thumbnailContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Show animated GIF on hover, video hover view, or regular thumbnail
                if item.isAnimated && animateGIFs && isHovering {
                    AsyncAnimatedGIFView(
                        item: item,
                        size: CGSize(width: size.pixelSize, height: size.pixelSize)
                    )
                } else if item.isVideo && isHovering {
                    VideoHoverView(
                        item: item,
                        size: size,
                        hoverPosition: hoverPosition
                    )
                } else {
                    AsyncThumbnailImage(item: item, size: size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .overlay(alignment: .topLeading) {
                // Media type badge
                mediaBadge
            }
            .overlay(alignment: .topTrailing) {
                // Rating stars overlay
                if item.isRated {
                    ratingBadge
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Duration badge for videos (when not hovering)
                if item.isVideo && !isHovering, let duration = item.formattedDuration {
                    Text(duration)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
            .shadow(color: .black.opacity(isSelected ? 0.3 : 0.1), radius: isSelected ? 8 : 4)
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    isHovering = true
                    hoverLocation = location
                    // Calculate horizontal position as 0.0 - 1.0
                    hoverPosition = max(0, min(1, location.x / geometry.size.width))
                case .ended:
                    isHovering = false
                }
            }
            .draggable(item.id.uuidString) {
                AsyncThumbnailImage(item: item, size: .small)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .onTapGesture(count: 2) {
                onDoubleTap()
            }
            .onTapGesture {
                onTap()
            }
        }
    }

    @ViewBuilder
    private var mediaBadge: some View {
        if item.mediaType == .gif {
            Text("GIF")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(6)
        } else if item.isVideo {
            Image(systemName: "play.fill")
                .font(.caption2)
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .padding(6)
        }
    }

    @ViewBuilder
    private var ratingBadge: some View {
        HStack(spacing: 1) {
            ForEach(1...item.effectiveRating, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
            }
        }
        .foregroundStyle(.yellow)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(6)
    }
}
