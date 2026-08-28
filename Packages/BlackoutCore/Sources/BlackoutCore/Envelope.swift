import Foundation

/// Opaque mesh unit. Mesh is a dumb pipe and must not inspect ciphertext.
public struct Envelope: Hashable, Codable, Sendable, Identifiable {
    public var id: BlackoutID
    public var kind: PayloadKind
    public var timestamp: Date
    public var ciphertext: Data
    public var sender: BlackoutID
    public var recipient: BlackoutID

    public init(
        id: BlackoutID = BlackoutID(),
        kind: PayloadKind,
        timestamp: Date = Date(),
        ciphertext: Data,
        sender: BlackoutID,
        recipient: BlackoutID
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.ciphertext = ciphertext
        self.sender = sender
        self.recipient = recipient
    }
}
