import SwiftUI

struct SlideshowSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Timing") {
                HStack {
                    Text("Slide duration")
                    Spacer()
                    TextField("", value: $settings.defaultImageDuration, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text("seconds")
                }
            }

            Section("Transitions") {
                Picker("Effect", selection: $settings.slideshowTransition) {
                    ForEach(TransitionType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                if settings.slideshowTransition != .none {
                    HStack {
                        Text("Duration")
                        Slider(value: $settings.slideshowTransitionDuration, in: 0.2...2.0, step: 0.1)
                        Text(String(format: "%.1fs", settings.slideshowTransitionDuration))
                            .frame(width: 40)
                    }
                }
            }

            Section("Playback") {
                Toggle("Loop slideshow", isOn: $settings.loopSlideshow)
                Toggle("Shuffle order", isOn: $settings.shuffleSlideshow)
            }

            Section("Video & GIF Playback") {
                Toggle("Limit video playback duration", isOn: Binding(
                    get: { !settings.videoPlayDuration.isFullVideo },
                    set: { settings.videoPlayDuration = $0 ? .fixed(30) : .fullVideo }
                ))

                Text("When on, videos advance after a set duration instead of playing to the end")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                    HStack {
                        Text("Background opacity")
                        Slider(value: $settings.captionBackgroundOpacity, in: 0.0...1.0)
                        Text("\(Int(settings.captionBackgroundOpacity * 100))%")
                            .frame(width: 40)
                    }
                }
            }

            Section("External Display") {
                Toggle("Show slideshow on external display", isOn: $settings.useAllMonitors)

                if settings.useAllMonitors {
                    Toggle("Show control panel", isOn: $settings.controlPanelOnSeparateMonitor)
                }
            }
        }
        .formStyle(.grouped)
    }
}
