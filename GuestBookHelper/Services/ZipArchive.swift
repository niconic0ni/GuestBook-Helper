import Compression
import Foundation

enum ZipArchiveError: LocalizedError {
    case invalidArchive
    case unsupportedCompression(UInt16)
    case entryNotFound(String)
    case decompressionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "不是有效的 xlsx（ZIP）文件。"
        case .unsupportedCompression(let method): return "xlsx 使用了不支持的压缩方式（\(method)）。"
        case .entryNotFound(let name): return "xlsx 中缺少 \(name)。"
        case .decompressionFailed(let name): return "无法解压 \(name)。"
        }
    }
}

struct ZipEntry {
    var name: String
    var compressionMethod: UInt16
    var compressedSize: Int
    var uncompressedSize: Int
    var localHeaderOffset: Int
}

final class ZipArchive {
    private let bytes: [UInt8]
    private(set) var entries: [String: ZipEntry] = [:]

    init(data: Data) throws {
        self.bytes = [UInt8](data)
        try parseCentralDirectory()
    }

    private func u16(_ offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private func u32(_ offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private func parseCentralDirectory() throws {
        guard bytes.count > 22 else { throw ZipArchiveError.invalidArchive }
        let minimum = max(0, bytes.count - 65_557)
        var eocd = -1
        var cursor = bytes.count - 22
        while cursor >= minimum {
            if u32(cursor) == 0x0605_4B50 {
                eocd = cursor
                break
            }
            cursor -= 1
        }
        guard eocd >= 0 else { throw ZipArchiveError.invalidArchive }
        let entryCount = Int(u16(eocd + 10))
        let directoryOffset = Int(u32(eocd + 16))
        guard directoryOffset >= 0 && directoryOffset < bytes.count else {
            throw ZipArchiveError.invalidArchive
        }

        var offset = directoryOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count, u32(offset) == 0x0201_4B50 else { break }
            let method = u16(offset + 10)
            let compressed = Int(u32(offset + 20))
            let uncompressed = Int(u32(offset + 24))
            let nameLength = Int(u16(offset + 28))
            let extraLength = Int(u16(offset + 30))
            let commentLength = Int(u16(offset + 32))
            let localOffset = Int(u32(offset + 42))
            guard offset + 46 + nameLength <= bytes.count else { break }
            let nameBytes = Array(bytes[(offset + 46)..<(offset + 46 + nameLength)])
            let name = String(bytes: nameBytes, encoding: .utf8)
                ?? String(bytes: nameBytes, encoding: .isoLatin1)
                ?? ""
            if !name.isEmpty && !name.hasSuffix("/") {
                entries[name] = ZipEntry(
                    name: name,
                    compressionMethod: method,
                    compressedSize: compressed,
                    uncompressedSize: uncompressed,
                    localHeaderOffset: localOffset
                )
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        guard !entries.isEmpty else { throw ZipArchiveError.invalidArchive }
    }

    func contains(_ name: String) -> Bool {
        entries[name] != nil
    }

    func data(for name: String) throws -> Data {
        guard let entry = entries[name] else { throw ZipArchiveError.entryNotFound(name) }
        let local = entry.localHeaderOffset
        guard local + 30 <= bytes.count, u32(local) == 0x0403_4B50 else {
            throw ZipArchiveError.invalidArchive
        }
        let nameLength = Int(u16(local + 26))
        let extraLength = Int(u16(local + 28))
        let dataStart = local + 30 + nameLength + extraLength
        guard dataStart + entry.compressedSize <= bytes.count else {
            throw ZipArchiveError.invalidArchive
        }
        let compressed = Array(bytes[dataStart..<(dataStart + entry.compressedSize)])
        switch entry.compressionMethod {
        case 0:
            return Data(compressed)
        case 8:
            return try inflate(compressed, expectedSize: entry.uncompressedSize, name: name)
        default:
            throw ZipArchiveError.unsupportedCompression(entry.compressionMethod)
        }
    }

    private func inflate(_ source: [UInt8], expectedSize: Int, name: String) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var destination = [UInt8](repeating: 0, count: expectedSize)
        let written = source.withUnsafeBufferPointer { sourceBuffer -> Int in
            guard let sourceBase = sourceBuffer.baseAddress else { return 0 }
            return destination.withUnsafeMutableBufferPointer { destinationBuffer -> Int in
                guard let destinationBase = destinationBuffer.baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase,
                    expectedSize,
                    sourceBase,
                    source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else {
            throw ZipArchiveError.decompressionFailed(name)
        }
        return Data(destination)
    }
}
