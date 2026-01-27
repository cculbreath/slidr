import Foundation

struct ImportOptions: Sendable {
    var copyToLibrary: Bool = true
    var convertIncompatible: Bool = true
    var deleteOriginalAfterConvert: Bool = false
    var targetFormat: VideoFormat = .h264MP4
    var organizeByDate: Bool = false

    static let `default` = ImportOptions()
}
