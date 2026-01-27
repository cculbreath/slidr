import SwiftUI
import UniformTypeIdentifiers

struct ImportDropZone: View {
    let isTargeted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary.opacity(0.5))

            VStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.largeTitle)
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

                Text("Drop files here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 100)
        .padding(.horizontal)
        .scaleEffect(isTargeted ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }
}

struct DropZoneModifier: ViewModifier {
    let supportedTypes: [UTType]
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    func body(content: Content) -> some View {
        content
            .onDrop(of: supportedTypes, isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                onDrop(urls)
            }
        }
    }
}

extension View {
    func dropZone(
        supportedTypes: [UTType] = FileTypeDetector.supportedUTTypes,
        isTargeted: Binding<Bool>,
        onDrop: @escaping ([URL]) -> Void
    ) -> some View {
        modifier(DropZoneModifier(
            supportedTypes: supportedTypes,
            isTargeted: isTargeted,
            onDrop: onDrop
        ))
    }
}
