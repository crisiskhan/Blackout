import Foundation

/// Persistence DTOs. SwiftData @Model types never leave the Persistence kit.

public struct ExpeditionRecordDTO: Hashable, Codable, Sendable, Identifiable {
    public var id: BlackoutID
    public var name: String
    public var notes: String
    public var createdAt: Date
    public var closedAt: Date?
    public var startLatitude: Double?
    public var startLongitude: Double?

    public init(
        id: BlackoutID = BlackoutID(),
        name: String,
        notes: String = "",
        createdAt: Date = Date(),
        closedAt: Date? = nil,
        startLatitude: Double? = nil,
        startLongitude: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
    }

    public var isOpen: Bool { closedAt == nil }
}

public struct BreadcrumbRecordDTO: Hashable, Codable, Sendable, Identifiable {
    public var id: BlackoutID
    public var expeditionID: BlackoutID
    public var recordedAt: Date
    public var latitude: Double?
    public var longitude: Double?

    public init(
        id: BlackoutID = BlackoutID(),
        expeditionID: BlackoutID,
        recordedAt: Date = Date(),
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.expeditionID = expeditionID
        self.recordedAt = recordedAt
        self.latitude = latitude
        self.longitude = longitude
    }

    public var hasCoordinate: Bool { latitude != nil && longitude != nil }
}

public struct SOSEventRecordDTO: Hashable, Codable, Sendable, Identifiable {
    public var id: BlackoutID
    public var armedAt: Date
    public var latitude: Double?
    public var longitude: Double?
    public var note: String

    public init(
        id: BlackoutID = BlackoutID(),
        armedAt: Date = Date(),
        latitude: Double? = nil,
        longitude: Double? = nil,
        note: String = ""
    ) {
        self.id = id
        self.armedAt = armedAt
        self.latitude = latitude
        self.longitude = longitude
        self.note = note
    }
}

public struct MessageRecordDTO: Hashable, Codable, Sendable, Identifiable {
    public var id: BlackoutID
    public var createdAt: Date
    public var ciphertext: Data
    public var status: MessageStatus
    public var senderID: BlackoutID
    public var recipientID: BlackoutID

    public init(
        id: BlackoutID = BlackoutID(),
        createdAt: Date = Date(),
        ciphertext: Data,
        status: MessageStatus,
        senderID: BlackoutID,
        recipientID: BlackoutID
    ) {
        self.id = id
        self.createdAt = createdAt
        self.ciphertext = ciphertext
        self.status = status
        self.senderID = senderID
        self.recipientID = recipientID
    }
}

public struct VoiceClipRecordDTO: Hashable, Codable, Sendable, Identifiable {
    public var id: BlackoutID
    public var createdAt: Date
    public var fileName: String
    public var durationSeconds: Double

    public init(
        id: BlackoutID = BlackoutID(),
        createdAt: Date = Date(),
        fileName: String,
        durationSeconds: Double
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fileName = fileName
        self.durationSeconds = durationSeconds
    }
}
