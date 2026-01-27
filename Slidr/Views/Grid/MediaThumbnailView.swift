import SwiftUI
import SwiftData

struct MediaThumbnailView: View {
    let item: MediaItem
    let size: ThumbnailSize
    let isSelected: Bool
    var selectedItemIDs: Set<UUID> = []
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @Query private var settingsQuery: [AppSettings]
    @State private var hoverState: HoverState = .idle

    private var settings: AppSettings? {
        settingsQuery.first
    }

    private var animateGIFs: Bool {
        settings?.animateGIFsInGrid ?? false
    }

    private var showFilenames: Bool {
        settings?.gridShowFilenames ?? false
    }

    private var showCaptions: Bool {
        settings?.gridShowCaptions ?? true
    }

    /// When the dragged item is part of a multi-selection, include all selected IDs
    /// so playlist drop targets receive the full set. IDs are newline-separated.
    private var dragPayload: String {
        if isSelected && selectedItemIDs.count > 1 {
            return selectedItemIDs.map(\.uuidString).joined(separator: "\n")
        }
        return item.id.uuidString
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

            if showCaptions, item.hasCaption {
                Text(item.caption ?? "")
                    .font(.caption2)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    .frame(width: size.pixelSize)
                    .italic()
            }
        }
    }

    private var thumbnailContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Show animated GIF on hover, video hover view, or regular thumbnail
                if item.isAnimated && animateGIFs {
                    AsyncAnimatedGIFView(
                        item: item,
                        size: CGSize(width: size.pixelSize, height: size.pixelSize)
                    )
                } else if item.isVideo && hoverState.isActive {
                    VideoHoverView(
                        item: item,
                        size: size,
                        hoverState: $hoverState
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
                if item.isVideo && !hoverState.isActive, let duration = item.formattedDuration {
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
            .scaleEffect(hoverState.isActive ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: hoverState.isActive)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let position = max(0, min(1, location.x / geometry.size.width))
                    hoverState = .scrubbing(position: position)
                case .ended:
                    hoverState = .idle
                }
            }
            .draggable(dragPayload) {
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
