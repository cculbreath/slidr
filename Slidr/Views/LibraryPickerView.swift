import SwiftUI
import OSLog

/// Shown at launch when the user holds Option or no valid last-used library exists.
/// Has no SwiftData dependencies — runs before ModelContainer is created.
struct LibraryPickerView: View {
    let manifestService: LibraryManifestService
    let onSelect: (LibraryReference) -> Void

    @State private var selectedID: UUID?
    @State private var showCreateSheet = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Choose a Library")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Hold Option on launch to see this dialog")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Library list
                libraryList
                    .frame(width: 480, height: min(CGFloat(manifestService.sortedLibraries.count) * 72 + 16, 320))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(width: 480)
                        .multilineTextAlignment(.center)
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button("Create New Library\u{2026}") {
                        showCreateSheet = true
                    }

                    Button("Locate Existing\u{2026}") {
                        locateExisting()
                    }
                }

                // Always-show toggle
                Toggle("Always show this dialog on startup", isOn: Binding(
                    get: { manifestService.manifest.alwaysShowPicker },
                    set: { newValue in
                        try? manifestService.setAlwaysShowPicker(newValue)
                    }
                ))
                .toggleStyle(.checkbox)
                .foregroundStyle(.secondary)

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCreateSheet) {
            CreateLibrarySheet(manifestService: manifestService) { ref in
                onSelect(ref)
            }
        }
    }

    // MARK: - Library List

    @ViewBuilder
    private var libraryList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(manifestService.sortedLibraries) { lib in
                    LibraryRowView(
                        library: lib,
                        isSelected: selectedID == lib.id,
                        onRemove: {
                            try? manifestService.removeReference(id: lib.id)
                        }
                    )
                    .onTapGesture {
                        guard lib.isAvailable else { return }
                        selectedID = lib.id
                    }
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            guard lib.isAvailable else { return }
                            onSelect(lib)
                        }
                    )
                    .onKeyPress(.return) {
                        if let id = selectedID,
                           let lib = manifestService.manifest.libraries.first(where: { $0.id == id }),
                           lib.isAvailable {
                            onSelect(lib)
                            return .handled
                        }
                        return .ignored
                    }
                }
            }
            .padding(8)
        }
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Locate Existing

    private func locateExisting() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Slidr library directory"
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let ref = try manifestService.addExistingLibrary(at: url)
            errorMessage = nil
            onSelect(ref)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Library Row

private struct LibraryRowView: View {
    let library: LibraryReference
    let isSelected: Bool
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: library.isAvailable ? "folder.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(library.isAvailable ? .blue : .orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(library.name)
                    .font(.headline)
                    .foregroundStyle(library.isAvailable ? .white : .white.opacity(0.5))

                Text(shortenedPath(library.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    if !library.isAvailable {
                        Text("Unavailable")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if let count = library.itemCount {
                        Text("\(count) items")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let date = library.lastOpenedDate {
                        Text("Last opened \(date, format: .relative(presentation: .named))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isHovering && !library.isDefault {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from list (does not delete files)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : (isHovering ? .white.opacity(0.05) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .opacity(library.isAvailable ? 1.0 : 0.6)
    }

    private func shortenedPath(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}

// MARK: - Create Library Sheet

struct CreateLibrarySheet: View {
    let manifestService: LibraryManifestService
    let onCreated: (LibraryReference) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var locationURL: URL?
    @State private var errorMessage: String?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Library")
                .font(.headline)

            TextField("Library Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)

            HStack {
                Text(locationLabel)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Choose\u{2026}") {
                    chooseLocation()
                }
            }
            .frame(width: 360)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(width: 360)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    createLibrary()
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty || locationURL == nil || isCreating)
            }
            .frame(width: 360)
        }
        .padding(24)
        .frame(width: 420)
    }

    private var locationLabel: String {
        if let url = locationURL {
            let path = url.path.replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path,
                with: "~"
            )
            return path
        }
        return "No location selected"
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to create the library"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            locationURL = url
        }
    }

    private func createLibrary() {
        guard let parentDir = locationURL, !name.isEmpty else { return }
        isCreating = true
        errorMessage = nil

        do {
            let ref = try manifestService.createLibrary(name: name, at: parentDir)
            dismiss()
            onCreated(ref)
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }
}
