import SwiftUI
import UniformTypeIdentifiers

struct DropZoneModifier: ViewModifier {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
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
            let supported = urls.filter { url in
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    return true
                }
                return FileTypeDetector.isSupported(url)
            }
            if !supported.isEmpty {
                onDrop(supported)
            }
        }
    }
}

extension View {
    func dropZone(
        isTargeted: Binding<Bool>,
        onDrop: @escaping ([URL]) -> Void
    ) -> some View {
        modifier(DropZoneModifier(
            isTargeted: isTargeted,
            onDrop: onDrop
        ))
    }
}
