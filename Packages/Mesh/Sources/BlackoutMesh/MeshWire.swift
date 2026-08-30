import BlackoutCore
import Foundation

/// Opaque radio frames. Mesh does not inspect ciphertext.
public enum MeshInbound: Equatable, Sendable {
    case advertisement(Data)
    case envelope(Envelope)
    case resource(name: String, fileURL: URL)
    /// Opaque live PTT bytes. Mesh must not inspect the payload.
    case pttFrame(Data)
    /// BK2+ or unknown kind on BK1. Not a silent skip.
    case unsupportedVersion

    public static let versionUnknownCopy = "Mesh version unknown."
}

enum MeshRadio {
    /// MCNearbyServiceAdvertiser service type: 1–15 ASCII letters / digits / hyphen.
    static let serviceType = "blckout-mesh"
    static let partyInfoKey = "p"
    static let deviceInfoKey = "i"

    /// Resource names are pack ids only (`el-paso`). Mesh does not parse zip bytes.
    static func isSafeResourceName(_ name: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return !name.isEmpty && name.count <= 32 && name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func discoveryInfo(partyCode: String, deviceID: BlackoutID) -> [String: String] {
        [
            partyInfoKey: partyCode,
            deviceInfoKey: deviceID.rawValue.uuidString
        ]
    }

    static func matchesParty(_ info: [String: String]?, partyCode: String) -> Bool {
        info?[partyInfoKey] == partyCode
    }

    static func shouldInvite(
        localID: BlackoutID,
        peerInfo: [String: String]?,
        peerDisplayName: String
    ) -> Bool {
        let peerKey = peerInfo?[deviceInfoKey] ?? peerDisplayName
        return localID.rawValue.uuidString < peerKey
    }
}

enum MeshWire {
    /// Frame magic is the envelope version. BK1 is v1. Do not add a second field.
    static let magic = Data([0x42, 0x4B, 0x31]) // BK1
    static let unsupportedVersionCopy = MeshInbound.versionUnknownCopy

    enum Kind: UInt8 {
        case advertisement = 1
        case envelope = 2
        case pttFrame = 3
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

    static func encodePTTFrame(_ payload: Data) -> Data {
        frame(kind: .pttFrame, payload: payload)
    }

    static func decode(_ data: Data) -> MeshInbound? {
        guard data.count >= 4 else { return nil }
        let prefix = data.prefix(3)
        if prefix == magic {
            guard let kind = Kind(rawValue: data[3]) else { return .unsupportedVersion }
            let payload = Data(data.dropFirst(4))
            switch kind {
            case .advertisement:
                return .advertisement(payload)
            case .envelope:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                guard let envelope = try? decoder.decode(Envelope.self, from: payload) else { return nil }
                return .envelope(envelope)
            case .pttFrame:
                return .pttFrame(payload)
            }
        }
        if prefix.count == 3, prefix[prefix.startIndex] == 0x42, prefix[prefix.startIndex + 1] == 0x4B {
            return .unsupportedVersion
        }
        return nil
    }

    private static func frame(kind: Kind, payload: Data) -> Data {
        var out = magic
        out.append(kind.rawValue)
        out.append(payload)
        return out
    }
}
