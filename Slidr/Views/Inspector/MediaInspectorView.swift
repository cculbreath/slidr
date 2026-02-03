import SwiftUI
import SwiftData

struct MediaInspectorView: View {
    @Bindable var item: MediaItem
    @Environment(MediaLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext

    @State private var isCopyingToLibrary = false
    @State private var showCopySuccess = false
    @State private var newTag: String = ""
    @State private var editedTitle: String = ""
    @State private var editedSummary: String = ""
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isSummaryFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with filename and type
                headerSection

                Divider()

                // Title
                titleSection

                Divider()

                // Caption
                CaptionEditorView(caption: $item.caption)

                Divider()

                // Source/Attribution
                sourceSection

                Divider()

                // Rating
                ratingSection

                Divider()

                // Production type
                productionSection

                Divider()

                // Summary
                summarySection

                if item.isVideo {
                    Divider()

                    // Transcript
                    TranscriptSection(item: item)
                }

                Divider()

                // Tags
                tagsSection

                Divider()

                // File info
                FileInfoSection(item: item, library: library)

                Divider()

                // Actions
                actionsSection
            }
            .padding()
        }
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 350)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(item.originalFilename)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            // Type badge
            HStack {
                Image(systemName: typeIcon)
                Text(item.mediaType.rawValue.capitalized)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var typeIcon: String {
        switch item.mediaType {
        case .image: return "photo"
        case .gif: return "play.square.stack"
        case .video: return "film"
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Show in Finder
            Button {
                showInFinder()
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // Copy to Library (only for referenced files)
            if item.storageLocation == .referenced {
                Button {
                    copyToLibrary()
                } label: {
                    if isCopyingToLibrary {
                        SpinnerView()
                    } else {
                        Label("Copy to Library", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isCopyingToLibrary)

                if showCopySuccess {
                    Text("Copied to library")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // Toggle favorite
            Button {
                item.isFavorite.toggle()
            } label: {
                Label(
                    item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: item.isFavorite ? "heart.fill" : "heart"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(item.isFavorite ? .pink : nil)
        }
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            SourceEditorView(source: $item.source, allLibrarySources: library.allSources)
        }
    }

    // MARK: - Rating Section

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rating")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        item.rating = item.rating == star ? nil : star
                    } label: {
                        Image(systemName: star <= (item.rating ?? 0) ? "star.fill" : "star")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(star <= (item.rating ?? 0) ? .yellow : .secondary)
                }

                if item.rating != nil {
                    Button {
                        item.rating = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear rating")
                    .padding(.leading, 4)
                }
            }
        }
    }

    // MARK: - Production Section

    private var productionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Production")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { item.production },
                set: { item.production = $0 }
            )) {
                Text("Not Set").tag(ProductionType?.none)
                ForEach(ProductionType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.iconName)
                        .tag(ProductionType?.some(type))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            TextField("Add title...", text: $editedTitle)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
        }
        .onAppear {
            editedTitle = item.title ?? ""
        }
        .onChange(of: item.title) { _, newValue in
            let incoming = newValue ?? ""
            if incoming != editedTitle {
                editedTitle = incoming
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused {
                let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                item.title = trimmed.isEmpty ? nil : trimmed
            }
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            TextEditor(text: $editedSummary)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .focused($isSummaryFocused)
                .overlay(alignment: .topLeading) {
                    if editedSummary.isEmpty && !isSummaryFocused {
                        Text("Add summary...")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .onAppear {
            editedSummary = item.summary ?? ""
        }
        .onChange(of: item.summary) { _, newValue in
            let incoming = newValue ?? ""
            if incoming != editedSummary {
                editedSummary = incoming
            }
        }
        .onChange(of: isSummaryFocused) { _, focused in
            if !focused {
                let trimmed = editedSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                item.summary = trimmed.isEmpty ? nil : trimmed
            }
        }
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            // Existing tags
            if !item.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(item.tags.sorted(), id: \.self) { tag in
                        TagChipView(tag: tag, onRemove: {
                            item.removeTag(tag)
                        })
                    }
                }
            }

            // Add new tag
            HStack {
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTag() }

                Button("Add") { addTag() }
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        item.addTag(tag)
        newTag = ""
    }

    // MARK: - Actions

    private func showInFinder() {
        let url = library.absoluteURL(for: item)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private func copyToLibrary() {
        isCopyingToLibrary = true
        Task {
            do {
                try await library.copyToLibrary(item)
                showCopySuccess = true

                // Hide success message after delay
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showCopySuccess = false
            } catch {
                // Error is already logged in MediaLibrary
            }
            isCopyingToLibrary = false
        }
    }
}
