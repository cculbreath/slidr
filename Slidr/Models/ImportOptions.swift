import Foundation

struct ImportOptions: Sendable {
    var importMode: ImportMode = .copy
    var storageLocation: StorageLocation = .local
    var convertIncompatible: Bool = true
    var deleteOriginalAfterConvert: Bool = false
    var targetFormat: VideoFormat = .h264MP4
    var organizeByDate: Bool = false

    static var `default`: ImportOptions { ImportOptions() }
}
