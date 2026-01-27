import SwiftUI

struct FolderPickerView: View {
    @Binding var folderPath: String
    let title: String
    let message: String
    var onPathChanged: ((URL?) -> Void)? = nil

    @State private var isValid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: folderIcon)
                    .foregroundStyle(folderPath.isEmpty ? Color.secondary : (isValid ? Color.blue : Color.red))

                if folderPath.isEmpty {
                    Text("No folder selected")
                        .foregroundStyle(.secondary)
                } else {
                    Text(displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Browse...") {
                    browseForFolder()
                }

                if !folderPath.isEmpty {
                    Button {
                        clearFolder()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if !isValid && !folderPath.isEmpty {
                Text("Folder does not exist or is not accessible")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: folderPath) { _, _ in
            validatePath()
        }
    }

    private var folderIcon: String {
        folderPath.isEmpty ? "folder" : (isValid ? "folder.fill" : "folder.badge.questionmark")
    }

    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if folderPath.hasPrefix(home) {
            return "~" + folderPath.dropFirst(home.count)
        }
        return folderPath
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = title
        panel.message = message

        if !folderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: folderPath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            onPathChanged?(url)
        }
    }

    private func clearFolder() {
        folderPath = ""
        onPathChanged?(nil)
    }

    private func validatePath() {
        if folderPath.isEmpty {
            isValid = true
            return
        }

        var isDirectory: ObjCBool = false
        isValid = FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
