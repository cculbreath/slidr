import SwiftUI

struct VideoHoverView: View {
    let item: MediaItem
    let size: ThumbnailSize
    let hoverPosition: CGFloat  // 0.0 to 1.0 across thumbnail width

    @Environment(MediaLibrary.self) private var library
    @State private var scrubThumbnails: [NSImage] = []
    @State private var isLoading = true

    private let thumbnailCount = 100

    var body: some View {
        ZStack {
            // Show appropriate scrub thumbnail based on hover position
            if !scrubThumbnails.isEmpty {
                let index = min(Int(hoverPosition * CGFloat(scrubThumbnails.count)), scrubThumbnails.count - 1)
                Image(nsImage: scrubThumbnails[max(0, index)])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                // Show static thumbnail while loading scrub thumbnails
                AsyncThumbnailImage(item: item, size: size)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            }

            // Duration badge
            if let duration = item.formattedDuration {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
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
            }

            // Scrub position indicator
            VStack {
                Spacer()
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 2, height: 4)
                        .position(x: geo.size.width * hoverPosition, y: 2)
                }
                .frame(height: 4)
            }
        }
        .task {
            await loadScrubThumbnails()
        }
    }

    private func loadScrubThumbnails() async {
        isLoading = true

        do {
            scrubThumbnails = try await library.videoScrubThumbnails(
                for: item,
                count: thumbnailCount,
                size: size
            )
        } catch {
            // Fall back to static thumbnail on error
            scrubThumbnails = []
        }

        isLoading = false
    }
}
