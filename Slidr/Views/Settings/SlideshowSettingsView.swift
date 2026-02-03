import SwiftUI

struct SlideshowSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
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

            Section("Captions") {
                Toggle("Show captions", isOn: $settings.showCaptions)

                if settings.showCaptions {
                    TextField("Caption template", text: $settings.captionTemplate)
                        .textFieldStyle(.roundedBorder)

                    Text("Variables: {filename}, {date}, {size}, {dimensions}, {duration}, {type}, {summary}")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Per-item captions take priority over the template. Variables work in custom captions too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Display mode", selection: $settings.captionDisplayMode) {
                        ForEach(CaptionDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Picker("Position", selection: $settings.captionPosition) {
                        if settings.captionDisplayMode == .overlay {
                            Text("Top").tag(CaptionPosition.top)
                            Text("Bottom").tag(CaptionPosition.bottom)
                            Text("Top Left").tag(CaptionPosition.topLeft)
                            Text("Top Right").tag(CaptionPosition.topRight)
                            Text("Bottom Left").tag(CaptionPosition.bottomLeft)
                            Text("Bottom Right").tag(CaptionPosition.bottomRight)
                        } else {
                            Text("Top").tag(CaptionPosition.top)
                            Text("Bottom").tag(CaptionPosition.bottom)
                        }
                    }
                    .onChange(of: settings.captionDisplayMode) { _, newMode in
                        if newMode == .outside && settings.captionPosition.isCornerPosition {
                            settings.captionPosition = .bottom
                        }
                    }

                    HStack {
                        Text("Font size")
                        Slider(value: $settings.captionFontSize, in: 10...80)
                        Text("\(Int(settings.captionFontSize))pt")
                            .frame(width: 40)
                    }

                    HStack {
                        Text("Background opacity")
                        Slider(value: $settings.captionBackgroundOpacity, in: 0.0...1.0)
                        Text("\(Int(settings.captionBackgroundOpacity * 100))%")
                            .frame(width: 40)
                    }

                    HStack {
                        Text("Video caption duration")
                        Slider(value: $settings.videoCaptionDuration, in: 3...15, step: 1)
                        Text("\(Int(settings.videoCaptionDuration))s")
                            .frame(width: 40)
                    }

                    Text("Captions on videos will show for this duration then fade out")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
