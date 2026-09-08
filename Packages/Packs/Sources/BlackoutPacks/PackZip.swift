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

    /// Store-only zip of a pack folder. Used when the original GitHub zip was not kept.
    /// Receiver still extracts via `extract`. Catalog SHA-256 matches only the kept GitHub zip.
    static func archive(directory: URL, to zipURL: URL) throws {
        let fm = FileManager.default
        let root = directory.standardizedFileURL
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw PackZipError.invalidArchive
        }
        var entries: [(name: String, data: Data)] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let full = file.standardizedFileURL.path
            let prefix = root.path
            guard full.hasPrefix(prefix + "/") else { continue }
            let rel = String(full.dropFirst(prefix.count + 1)).replacingOccurrences(of: "\\", with: "/")
            guard !rel.isEmpty, !rel.hasPrefix(".") else { continue }
            entries.append((rel, try Data(contentsOf: file, options: [.mappedIfSafe])))
        }
        guard !entries.isEmpty else { throw PackZipError.invalidArchive }
        entries.sort { $0.name < $1.name }

        var local = Data()
        var central = Data()
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = zipCRC32(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(local.count)
            var header = Data()
            header.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
            header.append(contentsOf: u16bytes(20))
            header.append(contentsOf: u16bytes(0))
            header.append(contentsOf: u16bytes(0))
            header.append(contentsOf: u16bytes(0))
            header.append(contentsOf: u16bytes(0))
            header.append(contentsOf: u32bytes(crc))
            header.append(contentsOf: u32bytes(size))
            header.append(contentsOf: u32bytes(size))
            header.append(contentsOf: u16bytes(UInt16(nameData.count)))
            header.append(contentsOf: u16bytes(0))
            local.append(header)
            local.append(nameData)
            local.append(entry.data)

            var dir = Data()
            dir.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
            dir.append(contentsOf: u16bytes(20))
            dir.append(contentsOf: u16bytes(20))
            dir.append(contentsOf: u16bytes(0))
            dir.append(contentsOf: u16bytes(0))
            dir.append(contentsOf: u16bytes(0))
            dir.append(contentsOf: u16bytes(0))
            dir.append(contentsOf: u32bytes(crc))
            dir.append(contentsOf: u32bytes(size))
            dir.append(contentsOf: u32bytes(size))
            dir.append(contentsOf: u16bytes(UInt16(nameData.count)))
            dir.append(contentsOf: u16bytes(0))
            dir.append(contentsOf: u16bytes(0))
            dir.append(contentsOf: u16bytes(0))
            dir.append(contentsOf: u16bytes(0))
            dir.append(contentsOf: u32bytes(0))
            dir.append(contentsOf: u32bytes(offset))
            central.append(dir)
            central.append(nameData)
        }
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        eocd.append(contentsOf: u16bytes(0))
        eocd.append(contentsOf: u16bytes(0))
        eocd.append(contentsOf: u16bytes(UInt16(entries.count)))
        eocd.append(contentsOf: u16bytes(UInt16(entries.count)))
        eocd.append(contentsOf: u32bytes(UInt32(central.count)))
        eocd.append(contentsOf: u32bytes(UInt32(local.count)))
        eocd.append(contentsOf: u16bytes(0))
        var zip = local
        zip.append(central)
        zip.append(eocd)
        try fm.createDirectory(at: zipURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try zip.write(to: zipURL, options: .atomic)
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
        try flattenRoot(destination)
    }

    /// If the zip wrapped the pack in one folder, promote `manifest.json` + `tiles/` to dest.
    static func flattenRoot(_ destination: URL) throws {
        let fm = FileManager.default
        let manifest = destination.appendingPathComponent("manifest.json")
        if fm.fileExists(atPath: manifest.path) { return }
        let contents = try fm.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let dirs = contents.filter { url in
            let name = url.lastPathComponent
            if name == "__MACOSX" { return false }
            return (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        guard dirs.count == 1 else { return }
        let nested = dirs[0]
        guard fm.fileExists(atPath: nested.appendingPathComponent("manifest.json").path) else { return }
        for item in try fm.contentsOfDirectory(at: nested, includingPropertiesForKeys: nil) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.moveItem(at: item, to: target)
        }
        try fm.removeItem(at: nested)
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

    private static func u16bytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private static func u32bytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ]
    }

    private static func zipCRC32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw -> UInt32 in
            let ptr = raw.bindMemory(to: Bytef.self).baseAddress
            return UInt32(crc32(0, ptr, uInt(data.count)))
        }
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
