import Foundation
import Compression

/// Native ZIP support without third-party code:
/// - zipping uses the system's NSFileCoordinator `.forUploading` archiver;
/// - unzipping is a minimal reader for standard ZIP (store + deflate),
///   inflating via the Compression framework.
enum ZipArchive {
    enum ZipError: LocalizedError {
        case zipFailed
        case notAZip
        case unsupportedCompression(UInt16)
        case corrupted

        var errorDescription: String? {
            switch self {
            case .zipFailed: return String(localized: "Could not create the archive.")
            case .notAZip: return String(localized: "The file is not a ZIP archive.")
            case .unsupportedCompression: return String(localized: "The archive uses an unsupported compression method.")
            case .corrupted: return String(localized: "The archive is damaged.")
            }
        }
    }

    /// Zips a folder into a temporary .zip and returns its URL.
    static func zip(folder: URL) throws -> URL {
        var resultURL: URL?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()
        // `.forUploading` makes the system produce a zip archive of the folder.
        coordinator.coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zippedURL in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(folder.lastPathComponent)-\(UUID().uuidString.prefix(6)).zip")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: zippedURL, to: dest)
                resultURL = dest
            } catch {
                resultURL = nil
            }
        }
        guard coordinationError == nil, let resultURL else { throw ZipError.zipFailed }
        return resultURL
    }

    /// Extracts a ZIP archive into the destination folder.
    static func unzip(_ zipURL: URL, to destination: URL) throws {
        let data = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        let entries = try centralDirectoryEntries(in: data)
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for entry in entries {
            // Reject absolute paths and traversal attempts.
            let name = entry.name.replacingOccurrences(of: "\\", with: "/")
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { continue }
            // Skip metadata noise the system archiver sometimes includes.
            if name.hasPrefix("__MACOSX/") || (name as NSString).lastPathComponent == ".DS_Store" { continue }

            let target = destination.appendingPathComponent(name)
            if name.hasSuffix("/") {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = try fileData(for: entry, in: data)
            try payload.write(to: target)
        }
    }

    // MARK: - ZIP format internals

    private struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private static func centralDirectoryEntries(in data: Data) throws -> [Entry] {
        // Find the End Of Central Directory record (signature 0x06054b50),
        // scanning backwards past a possible trailing comment.
        let eocdSignature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        guard data.count >= 22 else { throw ZipError.notAZip }
        var eocdOffset = -1
        let scanStart = max(0, data.count - 22 - 65_536)
        var i = data.count - 22
        while i >= scanStart {
            if data[i] == eocdSignature[0], data[i + 1] == eocdSignature[1],
               data[i + 2] == eocdSignature[2], data[i + 3] == eocdSignature[3] {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard eocdOffset >= 0 else { throw ZipError.notAZip }

        let entryCount = Int(readUInt16(data, eocdOffset + 10))
        var offset = Int(readUInt32(data, eocdOffset + 16))

        var entries: [Entry] = []
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, readUInt32(data, offset) == 0x0201_4b50 else { throw ZipError.corrupted }
            let method = readUInt16(data, offset + 10)
            let compressedSize = Int(readUInt32(data, offset + 20))
            let uncompressedSize = Int(readUInt32(data, offset + 24))
            let nameLength = Int(readUInt16(data, offset + 28))
            let extraLength = Int(readUInt16(data, offset + 30))
            let commentLength = Int(readUInt16(data, offset + 32))
            let localHeaderOffset = Int(readUInt32(data, offset + 42))
            guard offset + 46 + nameLength <= data.count else { throw ZipError.corrupted }
            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            entries.append(Entry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func fileData(for entry: Entry, in data: Data) throws -> Data {
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count, readUInt32(data, base) == 0x0403_4b50 else { throw ZipError.corrupted }
        let nameLength = Int(readUInt16(data, base + 26))
        let extraLength = Int(readUInt16(data, base + 28))
        let start = base + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupted }
        let compressed = data.subdata(in: start..<(start + entry.compressedSize))

        switch entry.method {
        case 0: // stored
            return compressed
        case 8: // deflate (Compression's ZLIB algorithm is raw DEFLATE)
            return try inflate(compressed, uncompressedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
    }

    private static func inflate(_ compressed: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        var output = Data(count: uncompressedSize)
        let written = output.withUnsafeMutableBytes { outPtr in
            compressed.withUnsafeBytes { inPtr in
                compression_decode_buffer(
                    outPtr.bindMemory(to: UInt8.self).baseAddress!, uncompressedSize,
                    inPtr.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == uncompressedSize else { throw ZipError.corrupted }
        return output
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
