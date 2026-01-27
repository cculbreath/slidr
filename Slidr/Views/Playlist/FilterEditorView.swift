import SwiftUI

struct FilterEditorView: View {
    @Binding var filterImages: Bool
    @Binding var filterVideos: Bool
    @Binding var filterGIFs: Bool
    @Binding var filterMinDuration: Double?
    @Binding var filterMaxDuration: Double?
    @Binding var filterFavoritesOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Media Types") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Images", isOn: $filterImages)
                    Toggle("Videos", isOn: $filterVideos)
                    Toggle("GIFs", isOn: $filterGIFs)
                }
                .toggleStyle(.checkbox)
                .padding(.vertical, 4)
            }

            GroupBox("Duration") {
                VStack(alignment: .leading, spacing: 12) {
                    DurationField(label: "Minimum", value: $filterMinDuration)
                    DurationField(label: "Maximum", value: $filterMaxDuration)

                    Text("Leave empty for no limit")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Other") {
                Toggle("Show favorites only", isOn: $filterFavoritesOnly)
                    .padding(.vertical, 4)
            }
        }
    }
}

struct DurationField: View {
    let label: String
    @Binding var value: Double?

    @State private var textValue: String = ""

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)

            TextField("", text: $textValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .onChange(of: textValue) { _, newValue in
                    if newValue.isEmpty {
                        value = nil
                    } else if let doubleValue = Double(newValue) {
                        value = doubleValue
                    }
                }

            Text("seconds")
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if let val = value {
                textValue = String(format: "%.0f", val)
            }
        }
    }
}
