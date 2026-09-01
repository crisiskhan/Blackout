import Foundation

/// Opaque mesh unit. Mesh is a dumb pipe and must not inspect ciphertext.
/// `hopCount` is pipe metadata (store-and-forward). Ciphertext stays unread.
public struct Envelope: Hashable, Codable, Sendable, Identifiable {
    public var id: BlackoutID
    public var kind: PayloadKind
    public var timestamp: Date
    public var ciphertext: Data
    public var sender: BlackoutID
    public var recipient: BlackoutID
    public var hopCount: Int

    public init(
        id: BlackoutID = BlackoutID(),
        kind: PayloadKind,
        timestamp: Date = Date(),
        ciphertext: Data,
        sender: BlackoutID,
        recipient: BlackoutID,
        hopCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.ciphertext = ciphertext
        self.sender = sender
        self.recipient = recipient
        self.hopCount = hopCount
    }

    public func forwarded() -> Envelope {
        var next = self
        next.hopCount += 1
        return next
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, timestamp, ciphertext, sender, recipient, hopCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(BlackoutID.self, forKey: .id)
        kind = try container.decode(PayloadKind.self, forKey: .kind)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        ciphertext = try container.decode(Data.self, forKey: .ciphertext)
        sender = try container.decode(BlackoutID.self, forKey: .sender)
        recipient = try container.decode(BlackoutID.self, forKey: .recipient)
        hopCount = try container.decodeIfPresent(Int.self, forKey: .hopCount) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(ciphertext, forKey: .ciphertext)
        try container.encode(sender, forKey: .sender)
        try container.encode(recipient, forKey: .recipient)
        try container.encode(hopCount, forKey: .hopCount)
    }
}
