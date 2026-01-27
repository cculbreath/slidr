import SwiftUI

struct SlideshowControlPanel: View {
    @Bindable var viewModel: SlideshowViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if let item = viewModel.currentItem {
                VStack(spacing: 4) {
                    Text(item.originalFilename)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(viewModel.currentIndex + 1) of \(viewModel.activeItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.currentItemIsVideo {
                ProgressView(value: viewModel.scrubber.progress)
                    .progressViewStyle(.linear)
            }

            HStack(spacing: 24) {
                Button { viewModel.previous() } label: {
                    Image(systemName: "backward.fill").font(.title2)
                }
                .buttonStyle(.plain)

                Button { viewModel.togglePlayback() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill").font(.title)
                }
                .buttonStyle(.plain)

                Button { viewModel.next() } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }
                .buttonStyle(.plain)
            }

            if viewModel.currentItemHasAudio {
                HStack {
                    Button {
                        viewModel.toggleMute()
                    } label: {
                        Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .buttonStyle(.plain)
                    Slider(value: $viewModel.volume, in: 0...1)
                        .frame(width: 100)
                }
            }

            Button("Exit Slideshow") { onClose() }
                .keyboardShortcut(.escape)
        }
        .padding()
        .frame(width: 350)
    }
}
