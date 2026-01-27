import SwiftUI

struct CaptionView: View {
    let item: MediaItem
    let template: String
    let position: CaptionPosition
    let fontSize: Double
    var backgroundOpacity: Double = 0.6

    var body: some View {
        Text(processedCaption)
            .font(.system(size: fontSize))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.black.opacity(backgroundOpacity))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()
    }

    private var processedCaption: String {
        var result = template
        result = result.replacingOccurrences(of: "{filename}", with: item.originalFilename)
        result = result.replacingOccurrences(of: "{date}", with: formattedDate)
        result = result.replacingOccurrences(of: "{size}", with: formattedSize)
        result = result.replacingOccurrences(of: "{dimensions}", with: formattedDimensions)
        result = result.replacingOccurrences(of: "{duration}", with: formattedDuration)
        result = result.replacingOccurrences(of: "{type}", with: item.mediaType.rawValue.capitalized)
        return result
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: item.fileModifiedDate)
    }

    private var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: item.fileSize)
    }

    private var formattedDimensions: String {
        guard let w = item.width, let h = item.height else { return "Unknown" }
        return "\(w) \u{00D7} \(h)"
    }

    private var formattedDuration: String {
        guard let duration = item.duration else { return "N/A" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Caption Overlay Modifier

struct CaptionOverlay: ViewModifier {
    let item: MediaItem
    let showCaptions: Bool
    let template: String
    let position: CaptionPosition
    let fontSize: Double
    var backgroundOpacity: Double = 0.6

    func body(content: Content) -> some View {
        content.overlay(alignment: position.alignment) {
            if showCaptions {
                CaptionView(item: item, template: template, position: position, fontSize: fontSize, backgroundOpacity: backgroundOpacity)
                    .transition(.opacity)
            }
        }
    }
}

extension View {
    func caption(for item: MediaItem, show: Bool, template: String, position: CaptionPosition, fontSize: Double, backgroundOpacity: Double = 0.6) -> some View {
        modifier(CaptionOverlay(item: item, showCaptions: show, template: template, position: position, fontSize: fontSize, backgroundOpacity: backgroundOpacity))
    }
}
