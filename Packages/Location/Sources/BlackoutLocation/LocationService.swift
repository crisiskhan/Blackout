import BlackoutCore
import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
public final class LocationService: LocationServing {
    public private(set) var authorization: LocationAuthorization = .notDetermined
    public private(set) var lastKnown: LocationFix?
    public private(set) var headingDegrees: Double?
    public private(set) var isUpdating = false

    fileprivate let manager = CLLocationManager()
    private let engine = LocationEngine()
    private static let lastKnownKey = "com.crisiskhan.blackout.location.lastKnown"

    public init() {
        engine.owner = self
        manager.delegate = engine
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.headingFilter = 2
        authorization = Self.map(manager.authorizationStatus)
        lastKnown = Self.loadLastKnown()
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
    }

    public func stopUpdating() {
        isUpdating = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
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
    }

    fileprivate func applyLocation(_ location: CLLocation) {
        let fix = LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            courseDegrees: location.course >= 0 ? location.course : nil,
            headingDegrees: headingDegrees,
            timestamp: location.timestamp
        )
        lastKnown = fix
        persistLastKnown(fix)
    }

    fileprivate func applyHeading(_ heading: CLHeading) {
        headingDegrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
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

    private static func loadLastKnown() -> LocationFix? {
        guard let data = UserDefaults.standard.data(forKey: lastKnownKey) else { return nil }
        return try? JSONDecoder().decode(LocationFix.self, from: data)
    }

    private func persistLastKnown(_ fix: LocationFix) {
        if let data = try? JSONEncoder().encode(fix) {
            UserDefaults.standard.set(data, forKey: Self.lastKnownKey)
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
