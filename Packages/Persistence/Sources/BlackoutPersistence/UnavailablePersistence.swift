import BlackoutCore
import Foundation

public enum PersistenceUnavailable: Error, LocalizedError {
    case diskStore

    public var errorDescription: String? {
        "On-disk store failed to open. Blackout will not fall back to memory, so a kill cannot wipe a fake SOS / expedition / message log."
    }
}

/// Visible failure stand-in. Every call throws. Not a silent memory store.
@MainActor
public final class UnavailablePersistence: PersistenceServing {
    public init() {}

    public func expeditions() throws -> [ExpeditionRecordDTO] { throw PersistenceUnavailable.diskStore }
    public func upsertExpedition(_ record: ExpeditionRecordDTO) throws { throw PersistenceUnavailable.diskStore }
    public func breadcrumbs(expeditionID: BlackoutID) throws -> [BreadcrumbRecordDTO] { throw PersistenceUnavailable.diskStore }
    public func appendBreadcrumb(_ record: BreadcrumbRecordDTO) throws { throw PersistenceUnavailable.diskStore }
    public func sosEvents() throws -> [SOSEventRecordDTO] { throw PersistenceUnavailable.diskStore }
    public func logSOS(_ record: SOSEventRecordDTO) throws { throw PersistenceUnavailable.diskStore }
    public func messages() throws -> [MessageRecordDTO] { throw PersistenceUnavailable.diskStore }
    public func saveMessage(_ record: MessageRecordDTO) throws { throw PersistenceUnavailable.diskStore }
    public func voiceClips() throws -> [VoiceClipRecordDTO] { throw PersistenceUnavailable.diskStore }
    public func saveVoiceClip(_ record: VoiceClipRecordDTO) throws { throw PersistenceUnavailable.diskStore }
}
