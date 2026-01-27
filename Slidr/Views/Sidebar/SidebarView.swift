import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(MediaLibrary.self) private var library
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label {
                    HStack {
                        Text("All Media")
                        Spacer()
                        Text("\(library.itemCount)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } icon: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .tag(SidebarItem.allMedia)
            }

            Section("Playlists") {
                Text("Coming in Phase 3")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem {
                Button {
                    importFiles()
                } label: {
                    Label("Import", systemImage: "plus")
                }
            }
        }
    }

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .gif]

        if panel.runModal() == .OK {
            Task {
                _ = try? await library.importFiles(urls: panel.urls)
            }
        }
    }
}

enum SidebarItem: Hashable {
    case allMedia
    case playlist(UUID)
}
