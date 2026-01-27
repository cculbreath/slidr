import SwiftUI

struct CaptionEditorView: View {
    @Binding var caption: String?

    @State private var editedCaption: String = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Caption")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                if !isEditing {
                    Button {
                        startEditing()
                    } label: {
                        Text("Edit")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }

            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $editedCaption)
                        .font(.body)
                        .frame(minHeight: 60, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .focused($isFocused)

                    HStack {
                        Button("Cancel") {
                            cancelEditing()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        if !editedCaption.isEmpty {
                            Button("Clear") {
                                editedCaption = ""
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("Save") {
                            saveCaption()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.small)
                }
            } else {
                if let caption = caption, !caption.isEmpty {
                    Text(caption)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text("No caption")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
    }

    // MARK: - Actions

    private func startEditing() {
        editedCaption = caption ?? ""
        isEditing = true
        isFocused = true
    }

    private func cancelEditing() {
        isEditing = false
        editedCaption = ""
    }

    private func saveCaption() {
        let trimmed = editedCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        caption = trimmed.isEmpty ? nil : trimmed
        isEditing = false
    }
}
