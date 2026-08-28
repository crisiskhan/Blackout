import Foundation
import zlib

enum PackZipError: Error, Equatable {
    case invalidArchive
    case pathTraversal
    case inflateFailed
}

enum PackZip {
    static func extract(zipURL: URL, to destination: URL) throws {
        let data = try Data(contentsOf: zipURL, options: [.mappedIfSafe])
        try extract(data: data, to: destination)
    }

    static func extract(data: Data, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var offset = 0
        while offset + 30 <= data.count {
            if data[offset] != 0x50 || data[offset + 1] != 0x4B { break }
            if data[offset + 2] == 0x01 && data[offset + 3] == 0x02 { break }
            if data[offset + 2] == 0x05 && data[offset + 3] == 0x06 { break }
            guard data[offset + 2] == 0x03 && data[offset + 3] == 0x04 else {
                throw PackZipError.invalidArchive
            }
            let method = u16(data, offset + 8)
            let compressed = Int(u32(data, offset + 18))
            let uncompressed = Int(u32(data, offset + 22))
            let nameLen = Int(u16(data, offset + 26))
            let extraLen = Int(u16(data, offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLen
            guard nameEnd + extraLen + compressed <= data.count else {
                throw PackZipError.invalidArchive
            }
            let name = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8) ?? ""
            let payloadStart = nameEnd + extraLen
            let payload = data.subdata(in: payloadStart..<(payloadStart + compressed))
            offset = payloadStart + compressed
            if name.isEmpty || name.hasSuffix("/") { continue }
            let dest = try safeFileURL(destination: destination, entry: name)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            switch method {
            case 0:
                try payload.write(to: dest, options: .atomic)
            case 8:
                let inflated = try inflateRaw(payload, uncompressedSize: uncompressed)
                try inflated.write(to: dest, options: .atomic)
            default:
                throw PackZipError.invalidArchive
            }
        }
    }

    private static func safeFileURL(destination: URL, entry: String) throws -> URL {
        let dest = destination.appendingPathComponent(entry)
        let destPath = dest.standardizedFileURL.path
        let rootPath = destination.standardizedFileURL.path
        if destPath == rootPath || destPath.hasPrefix(rootPath + "/") {
            return dest
        }
        throw PackZipError.pathTraversal
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func inflateRaw(_ input: Data, uncompressedSize: Int) throws -> Data {
        if uncompressedSize == 0 { return Data() }
        var stream = z_stream()
        var output = Data(count: uncompressedSize)
        let initStatus = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { throw PackZipError.inflateFailed }
        defer { inflateEnd(&stream) }
        let status: Int32 = output.withUnsafeMutableBytes { outRaw in
            input.withUnsafeBytes { inRaw in
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: inRaw.bindMemory(to: Bytef.self).baseAddress!
                )
                stream.avail_in = uInt(input.count)
                stream.next_out = outRaw.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(uncompressedSize)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { throw PackZipError.inflateFailed }
        return output
    }
}
