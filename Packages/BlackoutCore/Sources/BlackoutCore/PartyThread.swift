import Foundation

/// Group thread identity is derived from the party code, never a random UUID title.
public enum PartyThread {
    public static let staleSeconds: TimeInterval = 90

    public static func groupID(partyCode: String) -> BlackoutID {
        let seed = Array("blackout-group-v1:\(partyCode)".utf8)
        var h1: UInt64 = 0xCBF29CE484222325
        var h2: UInt64 = 0x100000001B3
        for byte in seed {
            h1 ^= UInt64(byte)
            h1 = h1 &* 0x100000001B3
            h2 ^= UInt64(byte) &+ 1
            h2 = h2 &* 0xCBF29CE484222325
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: h1 >> (i * 8))
            bytes[8 + i] = UInt8(truncatingIfNeeded: h2 >> (i * 8))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return BlackoutID(uuid)
    }

    public static func isGroupRecipient(_ id: BlackoutID, partyCode: String?) -> Bool {
        guard let partyCode, PartyCode.isValid(partyCode) else { return false }
        return id == groupID(partyCode: partyCode)
    }

    public static func groupTitle(selfCallsign: String, peerCallsigns: [String]) -> String {
        let peers = peerCallsigns.map { Callsign.commit($0) }.filter { !$0.isEmpty }
        if peers.isEmpty {
            let mine = Callsign.commit(selfCallsign)
            if mine == Callsign.defaultValue { return "Party" }
            return "\(mine) party"
        }
        return peers.joined(separator: ", ")
    }

    public static func isStale(lastHeard: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastHeard) > staleSeconds
    }
}

public struct SealedChatBody: Hashable, Codable, Sendable {
    public var text: String
    public var latitude: Double?
    public var longitude: Double?
    public var pingId: String?
    public var replyId: String?
    public var noFix: Bool
    public var fixAgeSeconds: Double?

    public init(
        text: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        pingId: String? = nil,
        replyId: String? = nil,
        noFix: Bool = false,
        fixAgeSeconds: Double? = nil
    ) {
        self.text = text
        self.latitude = latitude
        self.longitude = longitude
        self.pingId = pingId
        self.replyId = replyId
        self.noFix = noFix
        self.fixAgeSeconds = fixAgeSeconds
    }

    public var hasPin: Bool { latitude != nil && longitude != nil }
    public var fieldPing: FieldPingID? { pingId.flatMap(FieldPingID.init(rawValue:)) }
    public var fieldReply: FieldReplyID? { replyId.flatMap(FieldReplyID.init(rawValue:)) }

    public func encodePlaintext() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data(text.utf8)
    }

    public static func decode(_ data: Data) -> SealedChatBody {
        if let body = try? JSONDecoder().decode(SealedChatBody.self, from: data) {
            return body
        }
        return SealedChatBody(text: String(data: data, encoding: .utf8) ?? "")
    }

    public func pinFootnote() -> String {
        if noFix || !hasPin { return SOSConfirm.noFix }
        guard let latitude, let longitude else { return SOSConfirm.noFix }
        var line = String(format: "%.5f, %.5f", latitude, longitude)
        if let fixAgeSeconds, fixAgeSeconds > 0 {
            let seconds = Int(fixAgeSeconds.rounded())
            line += " · \(seconds)s"
        }
        return line
    }

    enum CodingKeys: String, CodingKey {
        case text, latitude, longitude, pingId, replyId, noFix, fixAgeSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        pingId = try container.decodeIfPresent(String.self, forKey: .pingId)
        replyId = try container.decodeIfPresent(String.self, forKey: .replyId)
        noFix = try container.decodeIfPresent(Bool.self, forKey: .noFix) ?? false
        fixAgeSeconds = try container.decodeIfPresent(Double.self, forKey: .fixAgeSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(pingId, forKey: .pingId)
        try container.encodeIfPresent(replyId, forKey: .replyId)
        if noFix { try container.encode(true, forKey: .noFix) }
        try container.encodeIfPresent(fixAgeSeconds, forKey: .fixAgeSeconds)
    }
}

public enum ChatThreadKind: String, Sendable, Hashable {
    case group
    case dm
}

public struct ChatThreadRef: Hashable, Sendable, Identifiable {
    public var kind: ChatThreadKind
    public var peerID: BlackoutID?
    public var partyCode: String?

    public init(kind: ChatThreadKind, peerID: BlackoutID? = nil, partyCode: String? = nil) {
        self.kind = kind
        self.peerID = peerID
        self.partyCode = partyCode
    }

    public static func group(partyCode: String) -> ChatThreadRef {
        ChatThreadRef(kind: .group, partyCode: partyCode)
    }

    public static func dm(peerID: BlackoutID) -> ChatThreadRef {
        ChatThreadRef(kind: .dm, peerID: peerID)
    }

    public var id: BlackoutID {
        switch kind {
        case .group:
            return PartyThread.groupID(partyCode: partyCode ?? "")
        case .dm:
            return peerID ?? BlackoutID()
        }
    }

    public var recipientID: BlackoutID { id }
}

public enum CommsCopy {
    public static let noThreads =
        "No threads. Messages need an expedition or a paired device. Solo outing has no group."
    public static let meshOffBanner = "Mesh off. Messages will send when a peer is in range."
    public static let noPeersInRange = "No peers in range."
    public static let rosterEmpty = "No peers. Mesh is on. Range depends on terrain."
    public static let stale = "STALE"
    public static let retry = "Retry"
}

public enum PTTCopy {
    public static let noMeshPress = "No mesh. Send a text."
    public static let noMeshEmpty = "No one to hear you. PTT is live only. Use text. It will queue."
    public static let micDenied = "Microphone denied. Open Settings to talk. Text still works."
    public static let live = "LIVE"
}

public struct PTTDecision: Equatable, Sendable {
    public var allowsTransmit: Bool
    public var dimmed: Bool
    public var pressMessage: String?
    public var emptyMessage: String?
    public var shouldBuffer: Bool
    public var showOpenSettings: Bool

    public init(
        allowsTransmit: Bool,
        dimmed: Bool,
        pressMessage: String? = nil,
        emptyMessage: String? = nil,
        shouldBuffer: Bool = false,
        showOpenSettings: Bool = false
    ) {
        self.allowsTransmit = allowsTransmit
        self.dimmed = dimmed
        self.pressMessage = pressMessage
        self.emptyMessage = emptyMessage
        self.shouldBuffer = shouldBuffer
        self.showOpenSettings = showOpenSettings
    }

    public static func evaluate(
        nearbyPeerCount: Int,
        partyCode: String?,
        meshRunning: Bool,
        microphoneAllowed: Bool
    ) -> PTTDecision {
        if !microphoneAllowed {
            return PTTDecision(
                allowsTransmit: false,
                dimmed: true,
                pressMessage: PTTCopy.micDenied,
                emptyMessage: PTTCopy.micDenied,
                shouldBuffer: false,
                showOpenSettings: true
            )
        }
        let meshReady = meshRunning && MeshGate.allowsTraffic(partyCode: partyCode) && nearbyPeerCount > 0
        if !meshReady {
            return PTTDecision(
                allowsTransmit: false,
                dimmed: true,
                pressMessage: PTTCopy.noMeshPress,
                emptyMessage: PTTCopy.noMeshEmpty,
                shouldBuffer: false
            )
        }
        return PTTDecision(allowsTransmit: true, dimmed: false, shouldBuffer: false)
    }
}

/// Live PTT is half-duplex. Refused presses must not enqueue audio.
public enum LivePTTLogic {
    public static func beginTalk(decision: PTTDecision, buffer: inout [Data]) -> Bool {
        buffer.removeAll()
        guard decision.allowsTransmit, !decision.shouldBuffer else { return false }
        return true
    }

    public static func liveFrame(decision: PTTDecision, transmitting: Bool, frame: Data) -> Data? {
        guard decision.allowsTransmit, transmitting, !decision.shouldBuffer else { return nil }
        return frame
    }
}
