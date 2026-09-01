import BlackoutCore
import Foundation
import MapsRouting
import Observation

@MainActor
@Observable
final class NavigateSession {
    enum Phase: Equatable {
        case idle
        case preview
        case guidance
    }

    var profile: NavigateProfile {
        didSet { UserDefaults.standard.set(profile.rawValue, forKey: BlackoutKeys.navigateProfile) }
    }
    var query = ""
    var hits: [PackSearchHit] = []
    var empty: NavigateEmpty?
    var destination: RoutingCoordinate?
    var destinationLabel: String?
    var preview: Route?
    var phase: Phase = .idle
    var muted: Bool {
        didSet { UserDefaults.standard.set(muted, forKey: BlackoutKeys.navigateMute) }
    }
    var tick: GuidanceTick?
    var attribution: String?
    var routingTooNew = false

    private var lastPrompt: String?
    private let speech = OnDeviceSpeech()

    init() {
        if let raw = UserDefaults.standard.string(forKey: BlackoutKeys.navigateProfile),
           let stored = NavigateProfile(rawValue: raw) {
            profile = stored
        } else {
            profile = .walk
        }
        muted = UserDefaults.standard.bool(forKey: BlackoutKeys.navigateMute)
    }

    var routePolyline: [RoutingCoordinate] {
        if phase == .guidance, let tick, case .routed(let next) = tick.reroute {
            return next.polyline
        }
        return preview?.polyline ?? []
    }

    var activeRoute: Route? {
        if phase == .guidance, let tick, case .routed(let next) = tick.reroute {
            return next
        }
        return preview
    }

    func search(pack: RoutingPack?, pois: [MapPOI], addresses: [MapAddress] = []) {
        if routingTooNew, pack == nil {
            hits = []
            empty = .packTooNew
            preview = nil
            destination = nil
            phase = .idle
            return
        }
        let result = PackSearch.query(
            query,
            pack: pack,
            pois: routingPOIs(pois),
            addresses: addresses.map {
                RoutingAddress(
                    id: $0.id,
                    house: $0.house,
                    street: $0.street,
                    coordinate: RoutingCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                )
            }
        )
        hits = result.hits
        empty = result.empty
        if result.empty != nil {
            preview = nil
            destination = nil
            phase = .idle
        }
    }

    func findPack(
        mode: PackFindMode,
        origin: RoutingCoordinate?,
        bounds: RoutingBBox?,
        pois: [MapPOI]
    ) {
        query = ""
        let result = PackFind.query(
            mode: mode,
            origin: origin,
            packBounds: bounds,
            pois: routingPOIs(pois)
        )
        hits = result.hits
        empty = result.empty
        preview = nil
        destination = nil
        destinationLabel = nil
        phase = .idle
        tick = nil
    }

    func pick(_ hit: PackSearchHit, origin: RoutingCoordinate?, pack: RoutingPack?) {
        query = hit.title
        hits = []
        setDestination(hit.coordinate, label: hit.title, origin: origin, pack: pack)
    }

    func pickMap(latitude: Double, longitude: Double, origin: RoutingCoordinate?, pack: RoutingPack?) {
        query = ""
        hits = []
        setDestination(
            RoutingCoordinate(latitude: latitude, longitude: longitude),
            label: "Dropped pin",
            origin: origin,
            pack: pack
        )
    }

    /// Last-used Walk / Drive (`profile`). Missing graph falls through to bearing-only.
    func navigateToPeer(
        latitude: Double,
        longitude: Double,
        label: String,
        origin: RoutingCoordinate?,
        pack: RoutingPack?
    ) {
        query = ""
        hits = []
        setDestination(
            RoutingCoordinate(latitude: latitude, longitude: longitude),
            label: label,
            origin: origin,
            pack: pack
        )
    }

    func markNoCoordinate() {
        empty = .noGPS
        preview = nil
        destination = nil
        destinationLabel = nil
        phase = .idle
    }

    func refreshPreview(origin: RoutingCoordinate?, pack: RoutingPack?) {
        guard let destination, phase != .guidance else { return }
        setDestination(destination, label: destinationLabel ?? "Destination", origin: origin, pack: pack)
    }

    func start(canFollow: Bool) {
        guard preview != nil else { return }
        guard canFollow else {
            empty = .noGPS
            return
        }
        empty = nil
        phase = .guidance
        lastPrompt = nil
        if let first = preview?.maneuvers.first, !muted {
            speak(VoicePrompt.phrase(for: first, distanceMeters: first.distanceMeters))
        }
    }

    func end() {
        phase = .idle
        preview = nil
        destination = nil
        destinationLabel = nil
        tick = nil
        empty = nil
        hits = []
        lastPrompt = nil
        speech.stop()
    }

    func park() {
        speech.teardown()
    }

    func update(
        position: RoutingCoordinate?,
        pack: RoutingPack?,
        canFollow: Bool
    ) {
        attribution = pack?.manifest.attribution
        guard phase == .guidance, let route = preview else { return }
        guard canFollow, let position else {
            empty = .noGPS
            return
        }
        let next = Guidance.tick(position: position, route: route, pack: pack, canReroute: true)
        if let reroute = next.reroute {
            switch reroute {
            case .noGraph:
                empty = .noGraph
                phase = .idle
                preview = nil
            case .offGraph:
                empty = .offGraph
            case .routed(let route):
                preview = route
                empty = nil
            }
        }
        tick = next
        if !muted, let maneuver = next.nextManeuver {
            let phrase = VoicePrompt.phrase(for: maneuver, distanceMeters: next.distanceToTurnMeters)
            if phrase != lastPrompt, next.distanceToTurnMeters < 180 {
                speak(phrase)
            }
        }
    }

    func toggleMute() {
        muted.toggle()
        if muted { speech.stop() }
    }

    func speakNow() {
        if muted { muted = false }
        if let maneuver = tick?.nextManeuver {
            speak(VoicePrompt.phrase(for: maneuver, distanceMeters: tick?.distanceToTurnMeters ?? maneuver.distanceMeters))
        } else if let first = preview?.maneuvers.first {
            speak(VoicePrompt.phrase(for: first, distanceMeters: first.distanceMeters))
        }
    }

    private func setDestination(
        _ coordinate: RoutingCoordinate,
        label: String,
        origin: RoutingCoordinate?,
        pack: RoutingPack?
    ) {
        destination = coordinate
        destinationLabel = label
        guard let pack else {
            empty = routingTooNew ? .packTooNew : .noGraph
            preview = nil
            phase = .idle
            return
        }
        guard let origin else {
            empty = .noGPS
            preview = nil
            phase = .idle
            return
        }
        switch PackRouter.route(from: origin, to: coordinate, profile: profile, pack: pack) {
        case .noGraph:
            empty = .noGraph
            preview = nil
            phase = .idle
        case .offGraph:
            empty = .offGraph
            preview = nil
            phase = .idle
        case .routed(let route):
            empty = nil
            preview = route
            phase = .preview
        }
    }

    private func speak(_ text: String) {
        lastPrompt = text
        speech.speak(text)
    }

    private func routingPOIs(_ pois: [MapPOI]) -> [RoutingPOI] {
        pois.map {
            RoutingPOI(
                id: $0.id,
                name: $0.name,
                kind: $0.kind,
                coordinate: RoutingCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            )
        }
    }
}
