import Foundation

@MainActor
public protocol PersistenceServing: AnyObject {
    func expeditions() throws -> [ExpeditionRecordDTO]
    func upsertExpedition(_ record: ExpeditionRecordDTO) throws
    func breadcrumbs(expeditionID: BlackoutID) throws -> [BreadcrumbRecordDTO]
    func appendBreadcrumb(_ record: BreadcrumbRecordDTO) throws
    func sosEvents() throws -> [SOSEventRecordDTO]
    func logSOS(_ record: SOSEventRecordDTO) throws
    func messages() throws -> [MessageRecordDTO]
    func saveMessage(_ record: MessageRecordDTO) throws
    func voiceClips() throws -> [VoiceClipRecordDTO]
    func saveVoiceClip(_ record: VoiceClipRecordDTO) throws
}

@MainActor
public protocol CryptoServing: AnyObject {
    var localIdentity: BlackoutID { get }
    func seal(_ plaintext: Data, to recipient: BlackoutID) throws -> Data
    func open(_ ciphertext: Data) throws -> Data
}

@MainActor
public protocol LocationServing: AnyObject {
    var authorization: LocationAuthorization { get }
    var lastKnown: LocationFix? { get }
    var manualPin: LocationFix? { get }
    var navigationFix: LocationFix? { get }
    var headingDegrees: Double? { get }
    var isUpdating: Bool { get }
    var isDeadReckoning: Bool { get }
    func requestWhenInUse()
    func startUpdating()
    func stopUpdating()
    func dropManualPin(latitude: Double, longitude: Double)
    func clearManualPin()
}

@MainActor
public protocol MeshServing: AnyObject {
    var nearbyPeerCount: Int { get }
    var statusLine: String { get }
    func start()
    func stop()
    func send(_ envelope: Envelope)
}

@MainActor
public protocol BatteryServing: AnyObject {
    var policy: BatteryPolicy { get set }
    var level: Float { get }
    var isCharging: Bool { get }
    var hidesSOS: Bool { get }
    var coarseNavigateEnabled: Bool { get }
    /// ≤2% and not charging. RootView must unmount Map/Comms/Field/Expedition. Never hide SOS.
    var isCritical: Bool { get }
    /// Named Extreme Saver profile while above 2%. 4-tab chrome, SOS + coarse nav + radar. Not last-2%.
    var isExtremeSaver: Bool { get }
    var pausesCameraAndPTT: Bool { get }
}

@MainActor
public protocol MapPackServing: AnyObject {
    var pack: MapPackSnapshot? { get }
    func elevationMeters(latitude: Double, longitude: Double) -> Double?
    func slopeDegrees(latitude: Double, longitude: Double) -> Double?
    func viewshed(fromLatitude: Double, fromLongitude: Double, observerHeightMeters: Double) -> [ViewshedRay]
}

@MainActor
public protocol AppLockServing: AnyObject {
    var isEnabled: Bool { get set }
    var isUnlocked: Bool { get }
    func lock()
    func unlock() async -> Bool
}

@MainActor
public protocol PermissionStatusServing: AnyObject {
    func status(for kind: PermissionKind) -> LocationAuthorization
}
