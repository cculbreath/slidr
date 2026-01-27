import SwiftUI

struct VolumeSlider: View {
    @Binding var volume: Float
    @Binding var isMuted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isMuted.toggle()
            } label: {
                Image(systemName: volumeIcon)
                    .font(.body)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)

            Slider(value: $volume, in: 0...1)
                .frame(width: 80)
                .disabled(isMuted)
                .opacity(isMuted ? 0.5 : 1.0)
        }
    }

    private var volumeIcon: String {
        if isMuted || volume == 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}
