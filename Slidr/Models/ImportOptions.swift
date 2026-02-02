import Foundation

struct ImportOptions: Sendable {
    var importMode: ImportMode
    var storageLocation: StorageLocation
    var convertIncompatible: Bool
    var deleteOriginalAfterConvert: Bool
    var targetFormat: VideoFormat
    var organizeByDate: Bool

    nonisolated init(
        importMode: ImportMode = .copy,
        storageLocation: StorageLocation = .local,
        convertIncompatible: Bool = true,
        deleteOriginalAfterConvert: Bool = false,
        targetFormat: VideoFormat = .h264MP4,
        organizeByDate: Bool = false
    ) {
        self.importMode = importMode
        self.storageLocation = storageLocation
        self.convertIncompatible = convertIncompatible
        self.deleteOriginalAfterConvert = deleteOriginalAfterConvert
        self.targetFormat = targetFormat
        self.organizeByDate = organizeByDate
    }
}
