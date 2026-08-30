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

    func search(pack: RoutingPack?, pois: [MapPOI]) {
        let mapped = pois.map {
            RoutingPOI(
                id: $0.id,
                name: $0.name,
                kind: $0.kind,
                coordinate: RoutingCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            )
        }
        let result = PackSearch.query(query, pack: pack, pois: mapped)
        hits = result.hits
        empty = result.empty
        if result.empty != nil {
            preview = nil
            destination = nil
            phase = .idle
        }
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

    private func setDestination(
        _ coordinate: RoutingCoordinate,
        label: String,
        origin: RoutingCoordinate?,
        pack: RoutingPack?
    ) {
        destination = coordinate
        destinationLabel = label
        guard let pack else {
            empty = .noGraph
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
}
