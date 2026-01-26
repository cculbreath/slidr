import SwiftUI

struct MediaThumbnailView: View {
    let item: MediaItem
    let size: ThumbnailSize
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        AsyncThumbnailImage(item: item, size: size)
            .frame(width: size.pixelSize, height: size.pixelSize)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .overlay(alignment: .topLeading) {
                // Media type badge
                if item.mediaType == .gif {
                    Text("GIF")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
            .shadow(color: .black.opacity(isSelected ? 0.3 : 0.1), radius: isSelected ? 8 : 4)
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
            .onTapGesture(count: 2) {
                onDoubleTap()
            }
            .onTapGesture {
                onTap()
            }
    }
}
