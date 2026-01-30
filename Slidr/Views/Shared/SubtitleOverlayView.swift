import SwiftUI
import CoreMedia

struct SubtitleOverlayView: View {
    let cues: [TranscriptCue]
    let scrubber: SmoothScrubber

    @State private var currentText: String = ""

    var body: some View {
        VStack {
            Spacer()
            if !currentText.isEmpty {
                Text(currentText)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black.opacity(0.7))
                    )
                    .padding(.horizontal, 40)
                    .padding(.bottom, 60)
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
