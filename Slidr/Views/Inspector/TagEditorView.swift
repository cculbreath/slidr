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
                        TagChip(
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
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredSuggestions.prefix(5), id: \.self) { suggestion in
                            Button {
                                newTagText = suggestion
                                addTag()
                            } label: {
                                Text(suggestion)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                            .background(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.1), radius: 4)
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

/// A single tag chip with optional remove button
struct TagChip: View {
    let tag: String
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
                .lineLimit(1)

            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
    }
}

/// A simple flow layout that wraps items to the next line
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let containerWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + rowHeight
        let totalWidth = containerWidth.isFinite ? containerWidth : frames.map { $0.maxX }.max() ?? 0

        return (CGSize(width: totalWidth, height: totalHeight), frames)
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
                        TagChip(tag: tag, onRemove: { removeTagFromAll(tag) })
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
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredSuggestions.prefix(5), id: \.self) { suggestion in
                            Button {
                                newTagText = suggestion
                                addTagToAll()
                            } label: {
                                Text(suggestion)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                            .background(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.1), radius: 4)
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
