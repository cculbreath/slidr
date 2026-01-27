import SwiftUI

struct CacheSettingsView: View {
    @Bindable var settings: AppSettings
    let thumbnailCache: ThumbnailCache

    @State private var cacheSize: String = "Calculating..."
    @State private var isClearing = false

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
                    Button("Clear Cache") {
                        clearCache()
                    }
                    .disabled(isClearing)
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
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            cacheSize = formatter.string(fromByteCount: Int64(size))
        }
    }

    private func clearCache() {
        isClearing = true
        Task {
            await thumbnailCache.clearCache()
            calculateCacheSize()
            isClearing = false
        }
    }
}
