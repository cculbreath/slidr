import SwiftUI

struct ProgressOverlay: View {
    let title: String
    let subtitle: String?
    let progress: Double?
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            if let progress = progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
            }

            Text(title)
                .font(.headline)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let onCancel = onCancel {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(minWidth: 250)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }
}

struct ProgressOverlayModifier: ViewModifier {
    let isPresented: Bool
    let title: String
    let subtitle: String?
    let progress: Double?
    let onCancel: (() -> Void)?

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isPresented)
                .blur(radius: isPresented ? 2 : 0)

            if isPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Allow clicking outside to cancel too
                        onCancel?()
                    }

                ProgressOverlay(
                    title: title,
                    subtitle: subtitle,
                    progress: progress,
                    onCancel: onCancel
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPresented)
        .onKeyPress(.escape) {
            guard isPresented, let onCancel else { return .ignored }
            onCancel()
            return .handled
        }
    }
}

extension View {
    func progressOverlay(
        isPresented: Bool,
        title: String,
        subtitle: String? = nil,
        progress: Double? = nil,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        modifier(ProgressOverlayModifier(
            isPresented: isPresented,
            title: title,
            subtitle: subtitle,
            progress: progress,
            onCancel: onCancel
        ))
    }
}

struct ImportProgressState {
    var isImporting = false
    var currentFile: String = ""
    var progress: Double = 0
    var totalFiles: Int = 0
    var processedFiles: Int = 0

    var subtitle: String {
        if totalFiles > 0 {
            return "\(processedFiles)/\(totalFiles): \(currentFile)"
        }
        return currentFile
    }
}
