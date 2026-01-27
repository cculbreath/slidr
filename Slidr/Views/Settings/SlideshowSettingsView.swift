import SwiftUI

struct SlideshowSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Timing") {
                HStack {
                    Text("Image duration")
                    Spacer()
                    TextField("", value: $settings.defaultImageDuration, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text("seconds")
                }

                HStack {
                    Text("GIF duration")
                    Spacer()
                    TextField("", value: $settings.defaultGIFDuration, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text("seconds")
                }
            }

            Section("Playback") {
                Toggle("Loop slideshow", isOn: $settings.loopSlideshow)
                Toggle("Shuffle order", isOn: $settings.shuffleSlideshow)
            }

            Section("Audio") {
                HStack {
                    Text("Default volume")
                    Slider(value: $settings.defaultVolume, in: 0...1)
                    Text("\(Int(settings.defaultVolume * 100))%")
                        .frame(width: 40)
                }

                Toggle("Mute by default", isOn: $settings.muteByDefault)
            }

            Section("Captions") {
                Toggle("Show captions", isOn: $settings.showCaptions)

                if settings.showCaptions {
                    TextField("Caption template", text: $settings.captionTemplate)
                        .textFieldStyle(.roundedBorder)

                    Text("Variables: {filename}, {date}, {size}, {dimensions}, {duration}")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Position", selection: $settings.captionPosition) {
                        Text("Top").tag(CaptionPosition.top)
                        Text("Bottom").tag(CaptionPosition.bottom)
                        Text("Top Left").tag(CaptionPosition.topLeft)
                        Text("Top Right").tag(CaptionPosition.topRight)
                        Text("Bottom Left").tag(CaptionPosition.bottomLeft)
                        Text("Bottom Right").tag(CaptionPosition.bottomRight)
                    }

                    HStack {
                        Text("Font size")
                        Slider(value: $settings.captionFontSize, in: 10...32)
                        Text("\(Int(settings.captionFontSize))pt")
                            .frame(width: 40)
                    }
                }
            }

            Section("Multi-Monitor") {
                Toggle("Use all monitors for slideshow", isOn: $settings.useAllMonitors)

                if settings.useAllMonitors {
                    Toggle("Show controls on separate monitor", isOn: $settings.controlPanelOnSeparateMonitor)
                }
            }
        }
        .formStyle(.grouped)
    }
}
