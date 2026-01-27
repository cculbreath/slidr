import SwiftUI

struct LibraryLocationPicker: View {
    let currentPath: String?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: String = ""
    @State private var migrateFiles = true

    var body: some View {
        VStack(spacing: 20) {
            Text("Choose Library Location")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Current location:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(currentPath ?? "Default Location")
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack {
                TextField("New location", text: $selectedPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Button("Browse...") {
                    browseForFolder()
                }
            }

            Toggle("Move existing files to new location", isOn: $migrateFiles)

            if !selectedPath.isEmpty {
                Text("Changing the library location may take time if you have many files.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Apply") {
                    onSelect(selectedPath)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(selectedPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 450)
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a location for the Slidr library"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }
}
