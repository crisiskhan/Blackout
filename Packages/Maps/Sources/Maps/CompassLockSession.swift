import BlackoutCore
import Foundation
import MapsRouting
import Observation

/// Field steer on the Map tab. Street TBT stays on `NavigateSession` when routing/ exists.
@MainActor
@Observable
final class CompassLockSession {
    var isLocked = false
    var target: CompassLockWaypoint?
    var marks: [CompassLockWaypoint]
    var markName = ""
    var showMarkSheet = false
    var emptyCopy: String?
    var origin: RoutingCoordinate?
    var headingDegrees: Double?

    private let speech = OnDeviceSpeech()
    private var voiceTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let marksKey: String

    init(
        defaults: UserDefaults = .standard,
        marksKey: String = BlackoutKeys.compassLockMarks
    ) {
        self.defaults = defaults
        self.marksKey = marksKey
        marks = Self.loadMarks(defaults: defaults, key: marksKey)
    }

    var lockCoordinate: RoutingCoordinate? { target?.coordinate }

    func refreshFix(origin: RoutingCoordinate?, heading: Double?) {
        self.origin = origin
        headingDegrees = heading
    }

    func openMark() {
        markName = CompassLockMath.defaultMarkName()
        emptyCopy = nil
        showMarkSheet = true
    }

    func openSteer() {
        emptyCopy = nil
        showMarkSheet = true
    }

    func saveCurrent(at fix: LocationFix?) -> Bool {
        guard let name = CompassLockMath.committedName(markName) else { return false }
        guard let fix, fix.hasCoordinate, let lat = fix.latitude, let lon = fix.longitude else {
            emptyCopy = NavigateCopy.noGPS
            return false
        }
        let point = CompassLockWaypoint(
            id: "mark-\(BlackoutID().rawValue.uuidString)",
            name: name,
            latitude: lat,
            longitude: lon,
            kind: .mark
        )
        marks.append(point)
        persistMarks()
        markName = CompassLockMath.defaultMarkName()
        emptyCopy = nil
        return true
    }

    func steer(_ point: CompassLockWaypoint) {
        target = point
        emptyCopy = nil
        syncVoiceLoop()
    }

    func markSearchHit(_ hit: PackSearchHit) {
        let point = CompassLockWaypoint(
            id: "mark-\(hit.id)",
            name: hit.title,
            latitude: hit.coordinate.latitude,
            longitude: hit.coordinate.longitude,
            kind: .mark
        )
        if !marks.contains(where: { $0.id == point.id }) {
            marks.append(point)
            persistMarks()
        }
        emptyCopy = nil
    }

    func lockOn(_ point: CompassLockWaypoint) -> Bool {
        target = point
        emptyCopy = nil
        isLocked = true
        syncVoiceLoop()
        return true
    }

    func deleteMark(_ point: CompassLockWaypoint) {
        guard point.canDelete else { return }
        marks.removeAll { $0.id == point.id }
        persistMarks()
        if target?.id == point.id {
            target = nil
            isLocked = false
            emptyCopy = CompassLockCopy.nothingToLock
        }
        syncVoiceLoop()
    }

    func toggleLock() {
        if target == nil {
            isLocked = false
            emptyCopy = CompassLockCopy.nothingToLock
            syncVoiceLoop()
            return
        }
        isLocked.toggle()
        emptyCopy = isLocked ? nil : emptyCopy
        syncVoiceLoop()
    }

    func speakOnce() {
        if target == nil {
            emptyCopy = CompassLockCopy.nothingToLock
            return
        }
        emptyCopy = nil
        if let text = currentPhrase() {
            speech.speak(text, rate: AudioChromeLock.clampedLockRate(CompassLockMath.speechRate))
        }
    }

    func end() {
        isLocked = false
        target = nil
        emptyCopy = nil
        showMarkSheet = false
        stopLoop()
    }

    func pickerRows(peers: [RadarBlip]) -> [CompassLockWaypoint] {
        CompassLockStandards.waypoints + marks + peers.compactMap(Self.waypoint(from:))
    }

    /// Starts the 2.2s loop only when it is not already running. Render must not call this.
    func syncVoiceLoop() {
        if isLocked, target != nil {
            startLoopIfNeeded()
        } else {
            stopLoop()
        }
    }

    private func startLoopIfNeeded() {
        guard voiceTask == nil else { return }
        voiceTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.utterLockPhrase()
                try? await Task.sleep(nanoseconds: UInt64(CompassLockMath.voiceInterval * 1_000_000_000))
            }
        }
    }

    private func stopLoop() {
        voiceTask?.cancel()
        voiceTask = nil
        speech.stop()
    }

    private func utterLockPhrase() {
        guard isLocked, target != nil, let text = currentPhrase() else { return }
        speech.speak(text, rate: AudioChromeLock.clampedLockRate(CompassLockMath.speechRate))
    }

    private func currentPhrase() -> String? {
        guard let target, let origin else { return nil }
        guard let heading = headingDegrees else { return nil }
        return CompassLockMath.phrase(
            name: target.name,
            origin: origin,
            target: target.coordinate,
            heading: heading
        )
    }

    private func persistMarks() {
        if let data = try? JSONEncoder().encode(marks) {
            defaults.set(data, forKey: marksKey)
        }
    }

    private static func loadMarks(defaults: UserDefaults, key: String) -> [CompassLockWaypoint] {
        guard let data = defaults.data(forKey: key),
              let rows = try? JSONDecoder().decode([CompassLockWaypoint].self, from: data) else {
            return []
        }
        return rows.filter { $0.kind == .mark }
    }

    private static func waypoint(from blip: RadarBlip) -> CompassLockWaypoint? {
        guard let lat = blip.latitude, let lon = blip.longitude else { return nil }
        let name = CompassLockMath.committedName(blip.displayName ?? "") ?? Callsign.defaultValue
        return CompassLockWaypoint(
            id: "peer-\(blip.id.rawValue.uuidString)",
            name: name,
            latitude: lat,
            longitude: lon,
            kind: .peer
        )
    }
}
