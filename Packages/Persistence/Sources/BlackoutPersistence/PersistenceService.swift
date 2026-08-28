import BlackoutCore
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class PersistenceService: PersistenceServing {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init() throws {
        let schema = Schema([
            ExpeditionRecord.self,
            BreadcrumbRecord.self,
            SOSEventRecord.self,
            MessageRecord.self,
            VoiceClipRecord.self
        ])
        let configuration = ModelConfiguration(
            "BlackoutLocal",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(for: schema, configurations: configuration)
    }

    public func expeditions() throws -> [ExpeditionRecordDTO] {
        let descriptor = FetchDescriptor<ExpeditionRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.dto() }
    }

    public func upsertExpedition(_ record: ExpeditionRecordDTO) throws {
        let target = record.id.rawValue
        let descriptor = FetchDescriptor<ExpeditionRecord>(
            predicate: #Predicate { $0.id == target }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.apply(record)
        } else {
            context.insert(ExpeditionRecord(record))
        }
        try context.save()
    }

    public func breadcrumbs(expeditionID: BlackoutID) throws -> [BreadcrumbRecordDTO] {
        let target = expeditionID.rawValue
        let descriptor = FetchDescriptor<BreadcrumbRecord>(
            predicate: #Predicate { $0.expeditionID == target },
            sortBy: [SortDescriptor(\.recordedAt, order: .forward)]
        )
        return try context.fetch(descriptor).map { $0.dto() }
    }

    public func appendBreadcrumb(_ record: BreadcrumbRecordDTO) throws {
        context.insert(BreadcrumbRecord(record))
        try context.save()
    }

    public func sosEvents() throws -> [SOSEventRecordDTO] {
        let descriptor = FetchDescriptor<SOSEventRecord>(
            sortBy: [SortDescriptor(\.armedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.dto() }
    }

    public func logSOS(_ record: SOSEventRecordDTO) throws {
        context.insert(SOSEventRecord(record))
        try context.save()
    }

    public func messages() throws -> [MessageRecordDTO] {
        let descriptor = FetchDescriptor<MessageRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.dto() }
    }

    public func saveMessage(_ record: MessageRecordDTO) throws {
        context.insert(MessageRecord(record))
        try context.save()
    }

    public func voiceClips() throws -> [VoiceClipRecordDTO] {
        let descriptor = FetchDescriptor<VoiceClipRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.dto() }
    }

    public func saveVoiceClip(_ record: VoiceClipRecordDTO) throws {
        context.insert(VoiceClipRecord(record))
        try context.save()
    }
}
