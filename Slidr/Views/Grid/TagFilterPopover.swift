import SwiftUI

struct TagFilterPopover: View {
    let allTags: [String]
    @Binding var tagFilter: Set<String>
    let hasTagFilter: Bool

    @State private var searchText = ""

    private var filteredTags: [String] {
        if searchText.isEmpty { return allTags }
        let query = searchText.lowercased()
        return allTags.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tags...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)

            Divider()

            if hasTagFilter {
                Button {
                    tagFilter.removeAll()
                } label: {
                    Label("Clear Tag Filter", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                Divider()
            }

            if allTags.isEmpty {
                Text("No tags in library")
                    .foregroundStyle(.secondary)
                    .padding()
            } else if filteredTags.isEmpty {
                Text("No matching tags")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredTags, id: \.self) { tag in
                            tagRow(tag)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 240)
    }

    private func tagRow(_ tag: String) -> some View {
        Button {
            if tagFilter.contains(tag) {
                tagFilter.remove(tag)
            } else {
                tagFilter.insert(tag)
            }
        } label: {
            HStack {
                Text(tag)
                    .lineLimit(1)
                Spacer()
                if tagFilter.contains(tag) {
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
}
