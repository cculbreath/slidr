import SwiftUI

struct CaptionEditorView: View {
    @Binding var caption: String?

    @State private var editedCaption: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Caption")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            TextEditor(text: $editedCaption)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .focused($isFocused)
                .overlay(alignment: .topLeading) {
                    if editedCaption.isEmpty && !isFocused {
                        Text("Add caption...")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .onAppear {
            editedCaption = caption ?? ""
        }
        .onChange(of: caption) { _, newValue in
            let incoming = newValue ?? ""
            if incoming != editedCaption {
                editedCaption = incoming
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                saveCaption()
            }
        }
    }

    private func saveCaption() {
        let trimmed = editedCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        caption = trimmed.isEmpty ? nil : trimmed
    }
}
