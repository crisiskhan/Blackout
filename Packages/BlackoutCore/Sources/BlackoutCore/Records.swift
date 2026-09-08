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
    /// Opt-in missed check-in. Default OFF. Local timer only — never auto-arms SOS.
    public var checkInEnabled: Bool
    public var checkInIntervalSeconds: Int
    public var lastCheckInAt: Date?

    public init(
        id: BlackoutID = BlackoutID(),
        name: String,
        notes: String = "",
        createdAt: Date = Date(),
        closedAt: Date? = nil,
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        checkInEnabled: Bool = false,
        checkInIntervalSeconds: Int = 1800,
        lastCheckInAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.checkInEnabled = checkInEnabled
        self.checkInIntervalSeconds = checkInIntervalSeconds
        self.lastCheckInAt = lastCheckInAt
    }

    public var isOpen: Bool { closedAt == nil }
}

public struct BreadcrumbRecordDTO: Hashable, Codable, Sendable, Identifiable {
    public var id: BlackoutID
    public var expeditionID: BlackoutID
    public var recordedAt: Date
    public var latitude: Double?
    public var longitude: Double?
    /// Dead-reckon / estimated. Never drawn as a GPS-quality point.
    public var estimated: Bool

    public init(
        id: BlackoutID = BlackoutID(),
        expeditionID: BlackoutID,
        recordedAt: Date = Date(),
        latitude: Double? = nil,
        longitude: Double? = nil,
        estimated: Bool = false
    ) {
        self.id = id
        self.expeditionID = expeditionID
        self.recordedAt = recordedAt
        self.latitude = latitude
        self.longitude = longitude
        self.estimated = estimated
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
    /// Bytes actually handed to the pipe. Optional so older rows still load.
    public var wireCiphertext: Data?

    public init(
        id: BlackoutID = BlackoutID(),
        createdAt: Date = Date(),
        ciphertext: Data,
        status: MessageStatus,
        senderID: BlackoutID,
        recipientID: BlackoutID,
        wireCiphertext: Data? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.ciphertext = ciphertext
        self.status = status
        self.senderID = senderID
        self.recipientID = recipientID
        self.wireCiphertext = wireCiphertext
    }

    public var meshBytes: Data { wireCiphertext ?? ciphertext }
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
