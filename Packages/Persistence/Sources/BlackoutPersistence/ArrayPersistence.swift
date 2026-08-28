import BlackoutCore
import Foundation

/// Last-resort store if SwiftData cannot open. Still returns DTOs, never @Model.
@MainActor
public final class ArrayPersistence: PersistenceServing {
    private var expeditionRows: [ExpeditionRecordDTO] = []
    private var breadcrumbRows: [BreadcrumbRecordDTO] = []
    private var sosRows: [SOSEventRecordDTO] = []
    private var messageRows: [MessageRecordDTO] = []
    private var voiceRows: [VoiceClipRecordDTO] = []

    public init() {}

    public func expeditions() throws -> [ExpeditionRecordDTO] {
        expeditionRows.sorted { $0.createdAt > $1.createdAt }
    }

    public func upsertExpedition(_ record: ExpeditionRecordDTO) throws {
        if let index = expeditionRows.firstIndex(where: { $0.id == record.id }) {
            expeditionRows[index] = record
        } else {
            expeditionRows.append(record)
        }
    }

    public func breadcrumbs(expeditionID: BlackoutID) throws -> [BreadcrumbRecordDTO] {
        breadcrumbRows.filter { $0.expeditionID == expeditionID }.sorted { $0.recordedAt < $1.recordedAt }
    }

    public func appendBreadcrumb(_ record: BreadcrumbRecordDTO) throws {
        breadcrumbRows.append(record)
    }

    public func sosEvents() throws -> [SOSEventRecordDTO] {
        sosRows.sorted { $0.armedAt > $1.armedAt }
    }

    public func logSOS(_ record: SOSEventRecordDTO) throws {
        sosRows.append(record)
    }

    public func messages() throws -> [MessageRecordDTO] {
        messageRows.sorted { $0.createdAt > $1.createdAt }
    }

    public func saveMessage(_ record: MessageRecordDTO) throws {
        messageRows.append(record)
    }

    public func voiceClips() throws -> [VoiceClipRecordDTO] {
        voiceRows.sorted { $0.createdAt > $1.createdAt }
    }

    public func saveVoiceClip(_ record: VoiceClipRecordDTO) throws {
        voiceRows.append(record)
    }
}
