import SwiftUI

struct TagPaletteView: View {
    @Bindable var viewModel: TagPaletteViewModel

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            searchField
            Divider()
            contentArea
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

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.mode {
        case .filter:
            filterContent
        case .editTags:
            editTagsContent
        }
    }

    // MARK: - Filter Mode

    private var filterContent: some View {
        VStack(spacing: 0) {
            if !viewModel.tagFilter.isEmpty {
                Button {
                    viewModel.clearFilter()
                } label: {
                    Label("Clear Tag Filter", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                Divider()
            }

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
                            filterTagRow(tag)
                        }
                    }
                }
            }
        }
    }

    private func filterTagRow(_ tag: String) -> some View {
        Button {
            viewModel.toggleFilterTag(tag)
        } label: {
            HStack {
                Text(tag)
                    .lineLimit(1)
                Spacer()
                if viewModel.tagFilter.contains(tag) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Edit Tags Mode

    private var editTagsContent: some View {
        VStack(spacing: 0) {
            if !viewModel.hasSelection {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "square.dashed")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Select media items to edit tags")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                editTagsHeader
                Divider()
                tagChips
                Divider()
                addTagField
            }
        }
    }

    private var editTagsHeader: some View {
        Text("Editing \(viewModel.selectedItems.count) item\(viewModel.selectedItems.count == 1 ? "" : "s")")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    private var tagChips: some View {
        ScrollView {
            FlowLayout(spacing: 4) {
                ForEach(Array(viewModel.partialTags).sorted(), id: \.self) { tag in
                    let isCommon = viewModel.commonTags.contains(tag)
                    tagChip(tag, isCommon: isCommon)
                }
            }
            .padding(8)
        }
    }

    private func tagChip(_ tag: String, isCommon: Bool) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.callout)
                .lineLimit(1)
            if !isCommon {
                Text("mixed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Button {
                viewModel.removeTagFromSelected(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isCommon ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
        .clipShape(Capsule())
        .opacity(isCommon ? 1.0 : 0.7)
    }

    @State private var newTagText: String = ""

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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
