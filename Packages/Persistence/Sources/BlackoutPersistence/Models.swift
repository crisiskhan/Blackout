import BlackoutCore
import Foundation
import SwiftData

@Model
final class ExpeditionRecord {
    var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var closedAt: Date?
    var startLatitude: Double?
    var startLongitude: Double?
    var checkInEnabled: Bool = false
    var checkInIntervalSeconds: Int = 1800
    var lastCheckInAt: Date?

    init(_ dto: ExpeditionRecordDTO) {
        id = dto.id.rawValue
        name = dto.name
        notes = dto.notes
        createdAt = dto.createdAt
        closedAt = dto.closedAt
        startLatitude = dto.startLatitude
        startLongitude = dto.startLongitude
        checkInEnabled = dto.checkInEnabled
        checkInIntervalSeconds = dto.checkInIntervalSeconds
        lastCheckInAt = dto.lastCheckInAt
    }

    func apply(_ dto: ExpeditionRecordDTO) {
        name = dto.name
        notes = dto.notes
        createdAt = dto.createdAt
        closedAt = dto.closedAt
        startLatitude = dto.startLatitude
        startLongitude = dto.startLongitude
        checkInEnabled = dto.checkInEnabled
        checkInIntervalSeconds = dto.checkInIntervalSeconds
        lastCheckInAt = dto.lastCheckInAt
    }

    func dto() -> ExpeditionRecordDTO {
        ExpeditionRecordDTO(
            id: BlackoutID(id),
            name: name,
            notes: notes,
            createdAt: createdAt,
            closedAt: closedAt,
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            checkInEnabled: checkInEnabled,
            checkInIntervalSeconds: checkInIntervalSeconds,
            lastCheckInAt: lastCheckInAt
        )
    }
}

@Model
final class BreadcrumbRecord {
    var id: UUID
    var expeditionID: UUID
    var recordedAt: Date
    var latitude: Double?
    var longitude: Double?

    init(_ dto: BreadcrumbRecordDTO) {
        id = dto.id.rawValue
        expeditionID = dto.expeditionID.rawValue
        recordedAt = dto.recordedAt
        latitude = dto.latitude
        longitude = dto.longitude
    }

    func dto() -> BreadcrumbRecordDTO {
        BreadcrumbRecordDTO(
            id: BlackoutID(id),
            expeditionID: BlackoutID(expeditionID),
            recordedAt: recordedAt,
            latitude: latitude,
            longitude: longitude
        )
    }
}

@Model
final class SOSEventRecord {
    var id: UUID
    var armedAt: Date
    var latitude: Double?
    var longitude: Double?
    var note: String

    init(_ dto: SOSEventRecordDTO) {
        id = dto.id.rawValue
        armedAt = dto.armedAt
        latitude = dto.latitude
        longitude = dto.longitude
        note = dto.note
    }

    func dto() -> SOSEventRecordDTO {
        SOSEventRecordDTO(
            id: BlackoutID(id),
            armedAt: armedAt,
            latitude: latitude,
            longitude: longitude,
            note: note
        )
    }
}

@Model
final class MessageRecord {
    var id: UUID
    var createdAt: Date
    var ciphertext: Data
    var statusRaw: String
    var senderID: UUID
    var recipientID: UUID
    var wireCiphertext: Data?

    init(_ dto: MessageRecordDTO) {
        id = dto.id.rawValue
        createdAt = dto.createdAt
        ciphertext = dto.ciphertext
        statusRaw = dto.status.rawValue
        senderID = dto.senderID.rawValue
        recipientID = dto.recipientID.rawValue
        wireCiphertext = dto.wireCiphertext
    }

    func apply(_ dto: MessageRecordDTO) {
        createdAt = dto.createdAt
        ciphertext = dto.ciphertext
        statusRaw = dto.status.rawValue
        senderID = dto.senderID.rawValue
        recipientID = dto.recipientID.rawValue
        wireCiphertext = dto.wireCiphertext
    }

    func dto() -> MessageRecordDTO {
        MessageRecordDTO(
            id: BlackoutID(id),
            createdAt: createdAt,
            ciphertext: ciphertext,
            status: MessageStatus(rawValue: statusRaw) ?? .sealed,
            senderID: BlackoutID(senderID),
            recipientID: BlackoutID(recipientID),
            wireCiphertext: wireCiphertext
        )
    }
}

@Model
final class VoiceClipRecord {
    var id: UUID
    var createdAt: Date
    var fileName: String
    var durationSeconds: Double

    init(_ dto: VoiceClipRecordDTO) {
        id = dto.id.rawValue
        createdAt = dto.createdAt
        fileName = dto.fileName
        durationSeconds = dto.durationSeconds
    }

    func dto() -> VoiceClipRecordDTO {
        VoiceClipRecordDTO(
            id: BlackoutID(id),
            createdAt: createdAt,
            fileName: fileName,
            durationSeconds: durationSeconds
        )
    }
}
