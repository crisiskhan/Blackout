import BlackoutCore
import Foundation

/// Seal → save → maybe mesh. Ciphertext stays on disk. Mesh is a dumb pipe.
@MainActor
public final class CommsOutbox {
    private let persistence: any PersistenceServing
    private let crypto: any CryptoServing
    private let transmit: (Envelope) -> MeshSendResult
    private let meshState: () -> (running: Bool, nearby: Int)

    public init(
        persistence: any PersistenceServing,
        crypto: any CryptoServing,
        transmit: @escaping (Envelope) -> MeshSendResult,
        meshState: @escaping () -> (running: Bool, nearby: Int)
    ) {
        self.persistence = persistence
        self.crypto = crypto
        self.transmit = transmit
        self.meshState = meshState
    }

    public func send(
        text: String,
        pin: LocationFix?,
        thread: ChatThreadRef
    ) throws -> MessageRecordDTO {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CommsOutboxError.empty }
        let body = SealedChatBody(
            text: trimmed,
            latitude: pin?.hasCoordinate == true ? pin?.latitude : nil,
            longitude: pin?.hasCoordinate == true ? pin?.longitude : nil
        )
        let plaintext = body.encodePlaintext()
        let display = try crypto.seal(plaintext, to: crypto.localIdentity)
        let wire = try wireSeal(plaintext, thread: thread)
        let state = meshState()
        var status: MessageStatus = .queued
        let record = MessageRecordDTO(
            ciphertext: display,
            status: status,
            senderID: crypto.localIdentity,
            recipientID: thread.recipientID,
            wireCiphertext: wire
        )
        try persistence.saveMessage(record)
        if state.running && state.nearby > 0 {
            status = transmit(envelope(for: record)).messageStatus
        } else {
            status = .queued
        }
        var saved = record
        saved.status = status
        try persistence.saveMessage(saved)
        return saved
    }

    public func ingest(_ envelope: Envelope) throws -> MessageRecordDTO? {
        guard envelope.kind == .message else { return nil }
        guard envelope.sender != crypto.localIdentity else { return nil }
        let existing = try persistence.messages()
        if let found = existing.first(where: { $0.id == envelope.id }) {
            return found
        }
        let display: Data
        if let opened = try? crypto.open(envelope.ciphertext) {
            display = (try? crypto.seal(opened, to: crypto.localIdentity)) ?? envelope.ciphertext
        } else {
            display = envelope.ciphertext
        }
        let record = MessageRecordDTO(
            id: envelope.id,
            createdAt: envelope.timestamp,
            ciphertext: display,
            status: .onMesh,
            senderID: envelope.sender,
            recipientID: envelope.recipient,
            wireCiphertext: envelope.ciphertext
        )
        try persistence.saveMessage(record)
        return record
    }

    @discardableResult
    public func flushQueued() throws -> [MessageRecordDTO] {
        let state = meshState()
        guard state.running, state.nearby > 0 else { return [] }
        var updated: [MessageRecordDTO] = []
        for var row in try persistence.messages() where row.status == .queued {
            let result = transmit(envelope(for: row))
            row.status = result.messageStatus
            try persistence.saveMessage(row)
            updated.append(row)
        }
        return updated
    }

    @discardableResult
    public func retry(_ id: BlackoutID) throws -> MessageRecordDTO? {
        guard var row = try persistence.messages().first(where: { $0.id == id }) else { return nil }
        let state = meshState()
        if !state.running || state.nearby == 0 {
            row.status = .queued
            try persistence.saveMessage(row)
            return row
        }
        row.status = transmit(envelope(for: row)).messageStatus
        try persistence.saveMessage(row)
        return row
    }

    public func messages() throws -> [MessageRecordDTO] {
        try persistence.messages()
    }

    public func openBody(_ record: MessageRecordDTO) -> SealedChatBody {
        if let data = try? crypto.open(record.ciphertext) {
            return SealedChatBody.decode(data)
        }
        if let wire = record.wireCiphertext, let data = try? crypto.open(wire) {
            return SealedChatBody.decode(data)
        }
        return SealedChatBody(text: "(unable to open)")
    }

    public func threads(partyCode: String?, peers: [(BlackoutID, String)], selfCallsign: String) throws -> [ChatThreadSummary] {
        let stored = try persistence.messages()
        var rows: [ChatThreadSummary] = []
        if let partyCode, PartyCode.isValid(partyCode) {
            let groupID = PartyThread.groupID(partyCode: partyCode)
            let groupRows = stored.filter {
                $0.recipientID == groupID || PartyThread.isGroupRecipient($0.recipientID, partyCode: partyCode)
            }
            rows.append(
                ChatThreadSummary(
                    ref: .group(partyCode: partyCode),
                    title: PartyThread.groupTitle(
                        selfCallsign: selfCallsign,
                        peerCallsigns: peers.map(\.1)
                    ),
                    lastBody: groupRows.first.map { openBody($0).text },
                    lastAt: groupRows.first?.createdAt
                )
            )
        }
        var seen: Set<BlackoutID> = []
        let local = crypto.localIdentity
        for record in stored {
            if PartyThread.isGroupRecipient(record.recipientID, partyCode: partyCode) { continue }
            let other = record.senderID == local ? record.recipientID : record.senderID
            if other == local { continue }
            if seen.contains(other) { continue }
            seen.insert(other)
            let name = peers.first(where: { $0.0 == other })?.1 ?? Callsign.defaultValue
            rows.append(
                ChatThreadSummary(
                    ref: .dm(peerID: other),
                    title: Callsign.commit(name),
                    lastBody: openBody(record).text,
                    lastAt: record.createdAt
                )
            )
        }
        return rows
    }

    public func messages(in thread: ChatThreadRef) throws -> [MessageRecordDTO] {
        let all = try persistence.messages()
        switch thread.kind {
        case .group:
            return all.filter { $0.recipientID == thread.recipientID }.reversed()
        case .dm:
            guard let peer = thread.peerID else { return [] }
            let local = crypto.localIdentity
            return all.filter { row in
                (row.senderID == local && row.recipientID == peer)
                    || (row.senderID == peer && (row.recipientID == local || row.recipientID == peer))
            }.reversed()
        }
    }

    private func wireSeal(_ plaintext: Data, thread: ChatThreadRef) throws -> Data {
        switch thread.kind {
        case .group:
            guard let code = thread.partyCode, PartyCode.isValid(code) else {
                return try crypto.seal(plaintext, to: crypto.localIdentity)
            }
            return try crypto.seal(plaintext, partyCode: code)
        case .dm:
            if let peer = thread.peerID {
                return try crypto.seal(plaintext, to: peer)
            }
            return try crypto.seal(plaintext, to: crypto.localIdentity)
        }
    }

    private func envelope(for record: MessageRecordDTO) -> Envelope {
        Envelope(
            id: record.id,
            kind: .message,
            timestamp: record.createdAt,
            ciphertext: record.meshBytes,
            sender: record.senderID,
            recipient: record.recipientID
        )
    }
}

public struct ChatThreadSummary: Identifiable, Hashable, Sendable {
    public var ref: ChatThreadRef
    public var title: String
    public var lastBody: String?
    public var lastAt: Date?

    public var id: BlackoutID { ref.id }

    public init(ref: ChatThreadRef, title: String, lastBody: String? = nil, lastAt: Date? = nil) {
        self.ref = ref
        self.title = title
        self.lastBody = lastBody
        self.lastAt = lastAt
    }
}

public enum CommsOutboxError: Error, LocalizedError {
    case empty

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Message is empty."
        }
    }
}
