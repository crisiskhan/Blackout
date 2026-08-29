import Foundation

enum RoutingReadError: Error, Equatable {
    case truncated
    case magic
    case count
}

struct LEReader {
    let data: Data
    var offset = 0

    var remaining: Int { data.count - offset }

    mutating func magic8() throws -> String {
        String(decoding: try raw(8), as: UTF8.self)
    }

    mutating func u16() throws -> UInt16 {
        let b = try raw(2)
        return UInt16(b[0]) | (UInt16(b[1]) << 8)
    }

    mutating func u32() throws -> UInt32 {
        let b = try raw(4)
        return UInt32(b[0])
            | (UInt32(b[1]) << 8)
            | (UInt32(b[2]) << 16)
            | (UInt32(b[3]) << 24)
    }

    mutating func i32() throws -> Int32 {
        Int32(bitPattern: try u32())
    }

    mutating func bytes(_ count: Int) throws -> Data {
        try raw(count)
    }

    private mutating func raw(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw RoutingReadError.truncated }
        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        return slice
    }
}

struct LEWriter {
    var data = Data()

    mutating func magic8(_ value: String) {
        let encoded = Array(value.utf8)
        precondition(encoded.count == 8)
        data.append(contentsOf: encoded)
    }

    mutating func u16(_ value: UInt16) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    mutating func u32(_ value: UInt32) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    mutating func i32(_ value: Int32) {
        u32(UInt32(bitPattern: value))
    }

    mutating func bytes(_ value: Data) {
        data.append(value)
    }
}
