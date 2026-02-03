import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("Slidr")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Version \(appVersion) (\(buildNumber))")
                .foregroundStyle(.secondary)

            Text("A native macOS media gallery viewer")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 4) {
                Text("Developed by Christopher Culbreath")
                    .font(.caption)

                Link("culbreath.net", destination: URL(string: "https://culbreath.net")!)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            Spacer()

            Text("\u{00A9} 2025-2026 Christopher Culbreath. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(width: 300, height: 400)
    }
}
