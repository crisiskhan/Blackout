import BlackoutCore
import CoreLocation
import CoreMotion
import Foundation
import Observation

@MainActor
@Observable
public final class LocationService: LocationServing {
    public private(set) var authorization: LocationAuthorization = .notDetermined
    public private(set) var lastKnown: LocationFix?
    public private(set) var manualPin: LocationFix?
    public private(set) var headingDegrees: Double?
    public private(set) var isUpdating = false
    public private(set) var isDeadReckoning = false
    public private(set) var deadReckoned: LocationFix?

    public var navigationFix: LocationFix? {
        if let lastKnown, lastKnown.hasCoordinate, lastKnown.source == .gps, isFresh(lastKnown) {
            return lastKnown
        }
        if isDeadReckoning, let deadReckoned, deadReckoned.hasCoordinate {
            return deadReckoned
        }
        if let lastKnown, lastKnown.hasCoordinate { return lastKnown }
        if let manualPin, manualPin.hasCoordinate { return manualPin }
        return lastKnown
    }

    fileprivate let manager = CLLocationManager()
    private let engine = LocationEngine()
    private let pedometer = CMPedometer()
    private let motion = CMMotionManager()
    private var origin: LocationFix?
    private var stepsSinceOrigin: Double = 0
    private var lastStepAt: Date?
    private var accelPeak = false
    private static let lastKnownKey = "com.crisiskhan.blackout.location.lastKnown"
    private static let manualPinKey = "com.crisiskhan.blackout.location.manualPin"
    /// Typical trail step. Pedometer distance wins when the OS provides it.
    private static let stepLengthMeters = 0.74
    private static let gpsStale: TimeInterval = 30

    public init() {
        engine.owner = self
        manager.delegate = engine
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.headingFilter = 2
        authorization = Self.map(manager.authorizationStatus)
        lastKnown = Self.load(Self.lastKnownKey)
        manualPin = Self.load(Self.manualPinKey)
        origin = lastKnown ?? manualPin
    }

    public func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    public func startUpdating() {
        isUpdating = true
        if authorization == .authorized {
            manager.startUpdatingLocation()
        }
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        startDeadReckoningSensors()
        refreshDeadReckoningFlag()
    }

    public func stopUpdating() {
        isUpdating = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        stopDeadReckoningSensors()
    }

    public func applyPolicy(_ policy: BatteryPolicy) {
        switch policy {
        case .balanced:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 5
        case .saver:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 25
        case .extremeSaver:
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.distanceFilter = 100
        }
    }

    fileprivate func applyAuthorization(_ status: CLAuthorizationStatus) {
        authorization = Self.map(status)
        if authorization == .authorized, isUpdating {
            manager.startUpdatingLocation()
        }
        refreshDeadReckoningFlag()
    }

    fileprivate func applyLocation(_ location: CLLocation) {
        let fix = LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            courseDegrees: location.course >= 0 ? location.course : nil,
            headingDegrees: headingDegrees,
            timestamp: location.timestamp,
            source: .gps
        )
        lastKnown = fix
        persist(fix, key: Self.lastKnownKey)
        origin = fix
        stepsSinceOrigin = 0
        deadReckoned = nil
        refreshDeadReckoningFlag()
    }

    fileprivate func applyHeading(_ heading: CLHeading) {
        headingDegrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        integrateDeadReckoning()
    }

    public func dropManualPin(latitude: Double, longitude: Double) {
        let fix = LocationFix(latitude: latitude, longitude: longitude, timestamp: Date(), source: .manualPin)
        manualPin = fix
        persist(fix, key: Self.manualPinKey)
        if lastKnown?.source != .gps || !isFresh(lastKnown) {
            origin = fix
            stepsSinceOrigin = 0
            integrateDeadReckoning()
        }
    }

    public func clearManualPin() {
        manualPin = nil
        UserDefaults.standard.removeObject(forKey: Self.manualPinKey)
        if lastKnown?.hasCoordinate != true {
            origin = nil
            deadReckoned = nil
        }
        refreshDeadReckoningFlag()
    }

    private func startDeadReckoningSensors() {
        if CMPedometer.isStepCountingAvailable() {
            let from = Date().addingTimeInterval(-1)
            pedometer.startUpdates(from: from) { [weak self] data, _ in
                guard let data else { return }
                Task { @MainActor in
                    self?.applyPedometer(data)
                }
            }
        }
        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 0.05
            motion.startAccelerometerUpdates(to: .main) { [weak self] sample, _ in
                guard let sample else { return }
                Task { @MainActor in
                    self?.applyAccelerometer(sample)
                }
            }
        }
    }

    private func stopDeadReckoningSensors() {
        pedometer.stopUpdates()
        motion.stopAccelerometerUpdates()
    }

    private func applyPedometer(_ data: CMPedometerData) {
        let steps = data.numberOfSteps.doubleValue
        if let distance = data.distance?.doubleValue, steps > 0 {
            stepsSinceOrigin = distance / Self.stepLengthMeters
        } else {
            stepsSinceOrigin = steps
        }
        integrateDeadReckoning()
    }

    private func applyAccelerometer(_ sample: CMAccelerometerData) {
        guard !CMPedometer.isStepCountingAvailable() else { return }
        let mag = sqrt(
            sample.acceleration.x * sample.acceleration.x
                + sample.acceleration.y * sample.acceleration.y
                + sample.acceleration.z * sample.acceleration.z
        )
        if mag > 1.35, !accelPeak {
            accelPeak = true
            let now = Date()
            if lastStepAt == nil || now.timeIntervalSince(lastStepAt!) > 0.28 {
                lastStepAt = now
                stepsSinceOrigin += 1
                integrateDeadReckoning()
            }
        } else if mag < 1.05 {
            accelPeak = false
        }
    }

    private func integrateDeadReckoning() {
        refreshDeadReckoningFlag()
        guard isDeadReckoning, let origin, origin.hasCoordinate else { return }
        let heading = headingDegrees ?? origin.headingDegrees ?? 0
        let meters = stepsSinceOrigin * Self.stepLengthMeters
        guard meters > 0.4 else {
            deadReckoned = LocationFix(
                latitude: origin.latitude,
                longitude: origin.longitude,
                altitudeMeters: origin.altitudeMeters,
                headingDegrees: heading,
                timestamp: Date(),
                source: .deadReckoning
            )
            return
        }
        let dest = Self.offset(
            latitude: origin.latitude!,
            longitude: origin.longitude!,
            meters: meters,
            bearingDegrees: heading
        )
        deadReckoned = LocationFix(
            latitude: dest.0,
            longitude: dest.1,
            altitudeMeters: origin.altitudeMeters,
            headingDegrees: heading,
            timestamp: Date(),
            source: .deadReckoning
        )
    }

    private func refreshDeadReckoningFlag() {
        let gpsLive = authorization == .authorized && lastKnown?.source == .gps && isFresh(lastKnown)
        let hasOrigin = (origin ?? lastKnown ?? manualPin)?.hasCoordinate == true
        isDeadReckoning = !gpsLive && hasOrigin
        if !isDeadReckoning {
            deadReckoned = nil
        } else if origin == nil {
            origin = lastKnown ?? manualPin
        }
    }

    private func isFresh(_ fix: LocationFix?) -> Bool {
        guard let fix else { return false }
        return Date().timeIntervalSince(fix.timestamp) < Self.gpsStale
    }

    private static func offset(latitude: Double, longitude: Double, meters: Double, bearingDegrees: Double) -> (Double, Double) {
        let r = 6_371_000.0
        let brng = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(meters / r) + cos(lat1) * sin(meters / r) * cos(brng))
        let lon2 = lon1 + atan2(
            sin(brng) * sin(meters / r) * cos(lat1),
            cos(meters / r) - sin(lat1) * sin(lat2)
        )
        return (lat2 * 180 / .pi, lon2 * 180 / .pi)
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        @unknown default: return .denied
        }
    }

    private static func load(_ key: String) -> LocationFix? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LocationFix.self, from: data)
    }

    private func persist(_ fix: LocationFix, key: String) {
        if let data = try? JSONEncoder().encode(fix) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

private final class LocationEngine: NSObject, CLLocationManagerDelegate {
    weak var owner: LocationService?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            owner?.applyAuthorization(manager.authorizationStatus)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            owner?.applyLocation(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            owner?.applyHeading(newHeading)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        _ = error
    }
}
