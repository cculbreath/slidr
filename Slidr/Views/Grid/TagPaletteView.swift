import SwiftUI

struct TagPaletteView: View {
    @Bindable var viewModel: TagPaletteViewModel

    @State private var newTagText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            Divider()
            appliedTagsSection
            Divider()
            searchField
            Divider()
            sortToggle
            tagChecklist
            Divider()
            bottomBar
        }
        .frame(minWidth: 220, minHeight: 250)
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("Mode", selection: $viewModel.mode) {
            ForEach(TagPaletteViewModel.Mode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(8)
    }

    // MARK: - Applied Tags Section

    @ViewBuilder
    private var appliedTagsSection: some View {
        switch viewModel.mode {
        case .filter:
            filterChipsSection
        case .editTags:
            editChipsSection
        }
    }

    @ViewBuilder
    private var filterChipsSection: some View {
        if !viewModel.tagFilter.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Applied Tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 4) {
                    ForEach(Array(viewModel.tagFilter).sorted(), id: \.self) { tag in
                        chipView(tag: tag, dimmed: false) {
                            viewModel.toggleFilterTag(tag)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var editChipsSection: some View {
        if !viewModel.hasSelection {
            VStack(spacing: 8) {
                Image(systemName: "square.dashed")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("Select items to edit tags")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                editTagsHeader

                if !viewModel.partialTags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(Array(viewModel.partialTags).sorted(), id: \.self) { tag in
                            let isCommon = viewModel.commonTags.contains(tag)
                            chipView(tag: tag, dimmed: !isCommon) {
                                viewModel.removeTagFromSelected(tag)
                            }
                        }
                    }
                }

                addTagField
            }
            .padding(8)
        }
    }

    private var editTagsHeader: some View {
        Group {
            if viewModel.selectedItems.count == 1,
               let item = viewModel.selectedItems.first {
                Text(item.originalFilename)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Editing \(viewModel.selectedItems.count) items")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func chipView(tag: String, dimmed: Bool, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.callout)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(dimmed ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
        .opacity(dimmed ? 0.7 : 1.0)
    }

    private var addTagField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
            TextField("Add tag\u{2026}", text: $newTagText)
                .textFieldStyle(.plain)
                .onSubmit {
                    viewModel.addTagToSelected(newTagText)
                    newTagText = ""
                }
            if !newTagText.isEmpty {
                Button {
                    viewModel.addTagToSelected(newTagText)
                    newTagText = ""
                } label: {
                    Image(systemName: "return")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search tags\u{2026}", text: $viewModel.searchText)
                .textFieldStyle(.plain)
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Sort Toggle

    private var sortToggle: some View {
        HStack {
            Spacer()
            Button {
                viewModel.tagSort = viewModel.tagSort == .alphabetical ? .byCount : .alphabetical
            } label: {
                Image(systemName: viewModel.tagSort == .alphabetical ? "textformat.abc" : "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(viewModel.tagSort == .alphabetical ? "Sort by count" : "Sort alphabetically")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Tag Checklist

    @ViewBuilder
    private var tagChecklist: some View {
        if viewModel.allTags.isEmpty {
            Spacer()
            Text("No tags in library")
                .foregroundStyle(.secondary)
            Spacer()
        } else if viewModel.filteredTags.isEmpty {
            Spacer()
            Text("No matching tags")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filteredTags, id: \.self) { tag in
                        checklistRow(tag)
                    }
                }
            }
        }
    }

    private func checklistRow(_ tag: String) -> some View {
        Button {
            switch viewModel.mode {
            case .filter:
                viewModel.toggleFilterTag(tag)
            case .editTags:
                toggleEditTag(tag)
            }
        } label: {
            HStack(spacing: 0) {
                checkmarkIndicator(for: tag)
                    .frame(width: 24, alignment: .center)

                Text(tag)
                    .lineLimit(1)

                Spacer()

                if let count = viewModel.tagCounts[tag] {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func checkmarkIndicator(for tag: String) -> some View {
        let (symbol, color, visible): (String, Color, Bool) = {
            switch viewModel.mode {
            case .filter:
                return ("checkmark", .accentColor, viewModel.tagFilter.contains(tag))
            case .editTags:
                if viewModel.commonTags.contains(tag) {
                    return ("checkmark", .accentColor, true)
                } else if viewModel.partialTags.contains(tag) {
                    return ("minus", .secondary, true)
                }
                return ("checkmark", .accentColor, false)
            }
        }()

        return Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .opacity(visible ? 1 : 0)
    }

    private func toggleEditTag(_ tag: String) {
        if viewModel.commonTags.contains(tag) {
            viewModel.removeTagFromSelected(tag)
        } else {
            viewModel.addTagToSelected(tag)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        Button {
            viewModel.onShowAdvancedFilter?()
        } label: {
            HStack {
                Text("Advanced Filter\u{2026}")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
