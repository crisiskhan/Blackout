import BlackoutCore
import Foundation

/// Opaque radio frames. Mesh does not inspect ciphertext.
public enum MeshInbound: Equatable, Sendable {
    case advertisement(Data)
    case envelope(Envelope)
}

enum MeshRadio {
    /// MCNearbyServiceAdvertiser service type: 1–15 ASCII letters / digits / hyphen.
    static let serviceType = "blckout-mesh"
}

enum MeshWire {
    static let magic = Data([0x42, 0x4B, 0x31]) // BK1

    enum Kind: UInt8 {
        case advertisement = 1
        case envelope = 2
    }

    static func encodeAdvertisement(_ payload: Data) -> Data {
        frame(kind: .advertisement, payload: payload)
    }

    static func encodeEnvelope(_ envelope: Envelope) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let payload = try? encoder.encode(envelope) else { return nil }
        return frame(kind: .envelope, payload: payload)
    }

    static func decode(_ data: Data) -> MeshInbound? {
        guard data.count >= 4, data.prefix(3) == magic else { return nil }
        guard let kind = Kind(rawValue: data[3]) else { return nil }
        let payload = Data(data.dropFirst(4))
        switch kind {
        case .advertisement:
            return .advertisement(payload)
        case .envelope:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            guard let envelope = try? decoder.decode(Envelope.self, from: payload) else { return nil }
            return .envelope(envelope)
        }
    }

    private static func frame(kind: Kind, payload: Data) -> Data {
        var out = magic
        out.append(kind.rawValue)
        out.append(payload)
        return out
    }
}
