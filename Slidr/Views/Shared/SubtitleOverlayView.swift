import SwiftUI
import CoreMedia

struct SubtitleOverlayView: View {
    let cues: [TranscriptCue]
    let scrubber: SmoothScrubber
    var position: CaptionPosition = .bottom
    var fontSize: Double = 16.0
    var backgroundOpacity: Double = 0.7

    @State private var currentText: String = ""

    var body: some View {
        ZStack(alignment: position.alignment) {
            Color.clear
            if !currentText.isEmpty {
                Text(currentText)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(position.isCornerPosition ? .leading : .center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black.opacity(backgroundOpacity))
                    )
                    .padding(.horizontal, 40)
                    .padding(edgePadding)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: currentText)
        .onChange(of: scrubber.currentTime) {
            updateCue()
        }
        .onAppear {
            updateCue()
        }
    }

    private var edgePadding: EdgeInsets {
        switch position {
        case .top:
            return EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 0)
        case .bottom:
            return EdgeInsets(top: 0, leading: 0, bottom: 60, trailing: 0)
        case .topLeft:
            return EdgeInsets(top: 60, leading: 20, bottom: 0, trailing: 0)
        case .topRight:
            return EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 20)
        case .bottomLeft:
            return EdgeInsets(top: 0, leading: 20, bottom: 60, trailing: 0)
        case .bottomRight:
            return EdgeInsets(top: 0, leading: 0, bottom: 60, trailing: 20)
        }
    }

    private func updateCue() {
        let time = scrubber.currentTime.seconds
        if let cue = TranscriptParser.activeCue(at: time, in: cues) {
            let stripped = cue.text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            if stripped != currentText {
                currentText = stripped
            }
        } else if !currentText.isEmpty {
            currentText = ""
        }
    }
}
