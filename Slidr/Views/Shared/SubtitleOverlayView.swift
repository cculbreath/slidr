import SwiftUI
import CoreMedia

struct SubtitleOverlayView: View {
    let cues: [TranscriptCue]
    let scrubber: SmoothScrubber
    var position: CaptionPosition = .bottom
    var fontSize: Double = 16.0
    var backgroundOpacity: Double = 0.7

    @State private var currentCueIndex: Int?
    @State private var speakerColors: [String: Color] = [:]
    @State private var hasMultipleSpeakers = false

    private static let speakerPalette: [Color] = [
        .cyan, .yellow, .green, .orange, .pink, .mint, .purple, .teal,
    ]

    var body: some View {
        ZStack(alignment: position.alignment) {
            Color.clear
            if let index = currentCueIndex, index < cues.count {
                subtitleContent(for: cues[index])
                    .padding(.horizontal, 40)
                    .padding(edgePadding)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: currentCueIndex)
        .onChange(of: scrubber.currentTime) {
            updateCue()
        }
        .onAppear {
            buildSpeakerColors()
            updateCue()
        }
    }

    @ViewBuilder
    private func subtitleContent(for cue: TranscriptCue) -> some View {
        if hasMultipleSpeakers {
            speakerColoredContent(for: cue)
        } else {
            plainContent(for: cue)
        }
    }

    private func plainContent(for cue: TranscriptCue) -> some View {
        let stripped = cue.text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return Text(stripped)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(position.isCornerPosition ? .leading : .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.black.opacity(backgroundOpacity))
            )
    }

    private func speakerColoredContent(for cue: TranscriptCue) -> some View {
        let segments = TranscriptParser.parseSpeakerSegments(cue.text)
        return VStack(alignment: position.isCornerPosition ? .leading : .center, spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                let color = segment.speaker.flatMap { speakerColors[$0] } ?? .white
                if let speaker = segment.speaker {
                    HStack(spacing: 0) {
                        Text("\(speaker): ")
                            .bold()
                        Text(segment.text)
                    }
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(color)
                } else {
                    Text(segment.text)
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .multilineTextAlignment(position.isCornerPosition ? .leading : .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.black.opacity(backgroundOpacity))
        )
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

    private func buildSpeakerColors() {
        let speakers = TranscriptParser.uniqueSpeakers(in: cues)
        hasMultipleSpeakers = speakers.count > 1
        var colors: [String: Color] = [:]
        for (index, speaker) in speakers.enumerated() {
            colors[speaker] = Self.speakerPalette[index % Self.speakerPalette.count]
        }
        speakerColors = colors
    }

    private func updateCue() {
        let time = scrubber.currentTime.seconds
        if let cue = TranscriptParser.activeCue(at: time, in: cues) {
            if currentCueIndex != cue.index {
                currentCueIndex = cue.index
            }
        } else if currentCueIndex != nil {
            currentCueIndex = nil
        }
    }
}
