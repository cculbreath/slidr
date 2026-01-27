import Foundation
import CryptoKit

struct ContentHasher {
    private static let chunkSize = 1024 * 1024  // 1MB

    /// Generate hash from first 1MB + last 1MB + file size
    /// Fast for large files while still detecting duplicates
    static func hash(fileAt url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        try fileHandle.seek(toOffset: 0)

        var hasher = SHA256()

        // Hash first chunk
        let firstChunk = try fileHandle.read(upToCount: chunkSize) ?? Data()
        hasher.update(data: firstChunk)

        // Hash last chunk (if file is larger than 2 chunks)
        if fileSize > UInt64(chunkSize * 2) {
            try fileHandle.seek(toOffset: fileSize - UInt64(chunkSize))
            let lastChunk = try fileHandle.read(upToCount: chunkSize) ?? Data()
            hasher.update(data: lastChunk)
        }

        // Include file size in hash
        var sizeBytes = fileSize
        hasher.update(data: Data(bytes: &sizeBytes, count: MemoryLayout<UInt64>.size))

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
