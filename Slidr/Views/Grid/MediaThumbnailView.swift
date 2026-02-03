import SwiftUI
import SwiftData

struct HoverCellAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct MediaThumbnailView: View {
    let item: MediaItem
    let size: ThumbnailSize
    let isSelected: Bool
    var selectedItemIDs: Set<UUID> = []
    @Binding var hoveredItemID: UUID?
    let onTap: () -> Void
    let onDoubleTap: (Double?) -> Void

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

    private var hoverEnabled: Bool {
        settings?.gridVideoHoverScrub ?? true
    }

    private var isImageHovering: Bool {
        hoveredItemID == item.id
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
                .frame(width: size.displaySize, height: size.displaySize)

            if showFilenames {
                Text(item.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(width: size.displaySize)
            }

            if showCaptions, item.hasCaption {
                Text(item.caption ?? "")
                    .font(.caption2)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    .frame(width: size.displaySize)
                    .italic()
            }
        }
    }

    private var thumbnailContent: some View {
        ZStack {
            if item.isAnimated && animateGIFs {
                AsyncAnimatedGIFView(item: item)
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
        .frame(width: size.displaySize, height: size.displaySize)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .overlay(alignment: .topLeading) {
            mediaBadge
        }
        .overlay(alignment: .topTrailing) {
            if item.isRated {
                ratingBadge
            }
        }
        .overlay(alignment: .bottomTrailing) {
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
        .scaleEffect(hoverEnabled && hoverState.isActive ? 1.15 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: hoverState.isActive)
        .onChange(of: hoverEnabled) { _, enabled in
            if !enabled {
                hoverState = .idle
                if hoveredItemID == item.id {
                    hoveredItemID = nil
                }
            }
        }
        .anchorPreference(key: HoverCellAnchorKey.self, value: .bounds) { anchor in
            isImageHovering ? anchor : nil
        }
        .onContinuousHover { phase in
            guard hoverEnabled else { return }
            switch phase {
            case .active(let location):
                // Require the cursor to be within the inner portion of the
                // thumbnail so that casually passing over doesn't trigger
                // scrubbing/hover effects.
                let inset = size.displaySize * 0.05
                let activeRect = CGRect(
                    x: inset, y: inset,
                    width: size.displaySize - inset * 2,
                    height: size.displaySize - inset * 2
                )
                guard activeRect.contains(location) else {
                    if item.isVideo {
                        hoverState = .idle
                    } else if hoveredItemID == item.id {
                        hoveredItemID = nil
                    }
                    return
                }
                if item.isVideo {
                    let position = max(0, min(1, (location.x - inset) / activeRect.width))
                    hoverState = .scrubbing(position: position)
                } else {
                    hoveredItemID = item.id
                }
            case .ended:
                if item.isVideo {
                    hoverState = .idle
                } else if hoveredItemID == item.id {
                    hoveredItemID = nil
                }
            }
        }
        .draggable(dragPayload) {
            AsyncThumbnailImage(item: item, size: .small)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onTapGesture(count: 2) {
            onDoubleTap(item.isVideo && hoverState.isActive ? hoverState.position : nil)
        }
        .onTapGesture {
            onTap()
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
