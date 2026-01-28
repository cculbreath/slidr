import SwiftUI

/// A text field editor for source attribution with autocomplete from existing library sources
struct SourceEditorView: View {
    @Binding var source: String?
    let allLibrarySources: [String]

    @State private var showSuggestions = false
    @FocusState private var isInputFocused: Bool

    private var sourceText: Binding<String> {
        Binding(
            get: { source ?? "" },
            set: { source = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                TextField("Source (e.g., website, artist)", text: sourceText)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onChange(of: sourceText.wrappedValue) { _, newValue in
                        showSuggestions = !newValue.isEmpty && !filteredSuggestions.isEmpty
                    }

                if source != nil && !source!.isEmpty {
                    Button {
                        source = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
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
                            source = suggestion
                            showSuggestions = false
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

    private var filteredSuggestions: [String] {
        let query = (source ?? "").lowercased()
        return allLibrarySources
            .filter { $0.lowercased().contains(query) && $0.lowercased() != query }
            .sorted()
    }
}

/// Multi-select version that sets the source on multiple items
struct MultiSelectSourceEditorView: View {
    let items: [MediaItem]
    let allLibrarySources: [String]

    @State private var sourceText = ""
    @State private var showSuggestions = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show if items have different sources
            if !commonSource.isEmpty {
                HStack {
                    Text("Current:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(commonSource)
                        .font(.caption)
                }
            } else if items.contains(where: { $0.source != nil }) {
                Text("(Multiple values)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    TextField("Set source for all...", text: $sourceText)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .onSubmit {
                            applySourceToAll()
                        }
                        .onChange(of: sourceText) { _, newValue in
                            showSuggestions = !newValue.isEmpty && !filteredSuggestions.isEmpty
                        }

                    if !sourceText.isEmpty {
                        Button {
                            applySourceToAll()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        clearSourceFromAll()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear source from all")
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Autocomplete suggestions
                if showSuggestions && isInputFocused {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredSuggestions.prefix(5), id: \.self) { suggestion in
                            Button {
                                sourceText = suggestion
                                applySourceToAll()
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

    private var commonSource: String {
        guard let first = items.first?.source, !first.isEmpty else { return "" }
        if items.dropFirst().allSatisfy({ $0.source == first }) {
            return first
        }
        return ""
    }

    private var filteredSuggestions: [String] {
        let query = sourceText.lowercased()
        return allLibrarySources
            .filter { $0.lowercased().contains(query) }
            .sorted()
    }

    private func applySourceToAll() {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        items.forEach { $0.source = source }
        sourceText = ""
        showSuggestions = false
    }

    private func clearSourceFromAll() {
        items.forEach { $0.source = nil }
        sourceText = ""
    }
}
