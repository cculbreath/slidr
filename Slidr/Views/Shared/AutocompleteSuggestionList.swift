import SwiftUI

/// A reusable autocomplete suggestion dropdown that appears below a text field.
/// Used by TagEditorView and SourceEditorView for consistent autocomplete behavior.
struct AutocompleteSuggestionList: View {
    let suggestions: [String]
    var maxVisible: Int = 5
    let onSelect: (String) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions.prefix(maxVisible), id: \.self) { suggestion in
                    Button {
                        onSelect(suggestion)
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
