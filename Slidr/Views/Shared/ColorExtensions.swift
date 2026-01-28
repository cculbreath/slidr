import SwiftUI

extension Color {
    init?(hex: String) {
        guard !hex.isEmpty else { return nil }
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Toolbar Background Modifier

struct ToolbarBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content.toolbarBackground(.visible, for: .windowToolbar)
        }
    }
}
