import SwiftUI

struct CacheSettingsView: View {
    @Bindable var settings: AppSettings
    let thumbnailCache: ThumbnailCache
    @Environment(MediaLibrary.self) private var library

    @State private var cacheSize: String = "Calculating..."
    @State private var isClearing = false
    @State private var isRegenerating = false
    @State private var regenProgress: Double = 0
    @State private var regenTotal: Int = 0
    @State private var regenCurrent: Int = 0
    @State private var clearSuccess = false

    var body: some View {
        Form {
            Section("Memory Cache") {
                HStack {
                    Text("Maximum items in memory")
                    Spacer()
                    TextField("", value: $settings.maxMemoryCacheItems, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Higher values use more RAM but improve scrolling performance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Disk Cache") {
                HStack {
                    Text("Maximum disk cache size")
                    Spacer()
                    TextField("", value: $settings.maxDiskCacheMB, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("MB")
                }

                HStack {
                    Text("Current cache size:")
                    Spacer()
                    Text(cacheSize)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    if clearSuccess {
                        Label("Cleared", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Clear Cache") {
                        clearCache()
                    }
                    .disabled(isClearing)
                }
            }

            Section("Scrub Thumbnails") {
                HStack {
                    Text("Frames per video")
                    Spacer()
                    TextField("", value: $settings.scrubThumbnailCount, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Number of thumbnail frames generated for video hover scrubbing. Higher values give smoother scrubbing but use more disk space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isRegenerating {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: regenProgress)
                        Text("Processing \(regenCurrent) of \(regenTotal) videos...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Spacer()
                        Button("Regenerate Scrub Thumbnails") {
                            regenerateScrubThumbnails()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            calculateCacheSize()
        }
    }

    private func calculateCacheSize() {
        Task {
            let size = await thumbnailCache.diskCacheSize()
            cacheSize = Formatters.formatFileSize(Int64(size))
        }
    }

    private func clearCache() {
        isClearing = true
        clearSuccess = false
        Task {
            defer { isClearing = false }
            await thumbnailCache.clearCache()
            calculateCacheSize()
            clearSuccess = true
            // Hide success indicator after a delay
            try? await Task.sleep(for: .seconds(2))
            clearSuccess = false
        }
    }

    private func regenerateScrubThumbnails() {
        isRegenerating = true
        regenProgress = 0
        regenCurrent = 0
        regenTotal = 0

        Task {
            defer { isRegenerating = false }
            let total = await library.regenerateScrubThumbnailsWithProgress(
                count: settings.scrubThumbnailCount
            ) { current, total in
                regenCurrent = current
                regenTotal = total
                regenProgress = total > 0 ? Double(current) / Double(total) : 0
            }

            if total == 0 {
                // No videos to process
                regenTotal = 0
            }

            calculateCacheSize()
        }
    }
}
