import SwiftUI

/// A chip-based tag editor with autocomplete for existing library tags
struct TagEditorView: View {
    @Binding var tags: [String]
    let allLibraryTags: [String]
    let allowRemoval: Bool

    @State private var newTagText = ""
    @State private var showSuggestions = false
    @FocusState private var isInputFocused: Bool

    init(tags: Binding<[String]>, allLibraryTags: [String], allowRemoval: Bool = true) {
        self._tags = tags
        self.allLibraryTags = allLibraryTags
        self.allowRemoval = allowRemoval
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tag chips
            if !tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        TagChipView(
                            tag: tag,
                            onRemove: allowRemoval ? { removeTag(tag) } : nil
                        )
                    }
                }
            }

            // Input field with autocomplete
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    TextField("Add tag...", text: $newTagText)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .onSubmit {
                            addTag()
                        }
                        .onChange(of: newTagText) { _, newValue in
                            showSuggestions = !newValue.isEmpty && !filteredSuggestions.isEmpty
                        }

                    if !newTagText.isEmpty {
                        Button {
                            addTag()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Autocomplete suggestions
                if showSuggestions && isInputFocused {
                    AutocompleteSuggestionList(suggestions: filteredSuggestions) { suggestion in
                        newTagText = suggestion
                        addTag()
                    }
                }
            }
        }
    }

    private var filteredSuggestions: [String] {
        let query = newTagText.lowercased()
        return allLibraryTags
            .filter { tag in
                tag.lowercased().contains(query) && !tags.contains(where: { $0.lowercased() == tag.lowercased() })
            }
            .sorted()
    }

    private func addTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        guard !tags.contains(where: { $0.lowercased() == tag.lowercased() }) else {
            newTagText = ""
            return
        }
        tags.append(tag)
        newTagText = ""
        showSuggestions = false
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0.lowercased() == tag.lowercased() }
    }
}

/// Multi-select version that adds tags to multiple items
struct MultiSelectTagEditorView: View {
    let items: [MediaItem]
    let allLibraryTags: [String]

    @State private var newTagText = ""
    @State private var showSuggestions = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show common tags (tags that all items share)
            if !commonTags.isEmpty {
                Text("Common tags:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 4) {
                    ForEach(commonTags, id: \.self) { tag in
                        TagChipView(tag: tag, onRemove: { removeTagFromAll(tag) })
                    }
                }
            }

            // Input field for adding tags to all items
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    TextField("Add tag to all...", text: $newTagText)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .onSubmit {
                            addTagToAll()
                        }
                        .onChange(of: newTagText) { _, newValue in
                            showSuggestions = !newValue.isEmpty && !filteredSuggestions.isEmpty
                        }

                    if !newTagText.isEmpty {
                        Button {
                            addTagToAll()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Autocomplete suggestions
                if showSuggestions && isInputFocused {
                    AutocompleteSuggestionList(suggestions: filteredSuggestions) { suggestion in
                        newTagText = suggestion
                        addTagToAll()
                    }
                }
            }
        }
    }

    private var commonTags: [String] {
        guard let first = items.first else { return [] }
        return first.tags.filter { tag in
            items.dropFirst().allSatisfy { $0.hasTag(tag) }
        }
    }

    private var filteredSuggestions: [String] {
        let query = newTagText.lowercased()
        return allLibraryTags
            .filter { tag in
                tag.lowercased().contains(query)
            }
            .sorted()
    }

    private func addTagToAll() {
        let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        items.forEach { $0.addTag(tag) }
        newTagText = ""
        showSuggestions = false
    }

    private func removeTagFromAll(_ tag: String) {
        items.forEach { $0.removeTag(tag) }
    }
}
