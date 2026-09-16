import CoreLocation
import Foundation
import MapLibre
import Router
import SwiftUI
import UIKit

/// MapLibre Metal map. Local style only. No MapKit, no tile hosts.
public struct OfflineMapView: UIViewRepresentable {
    public var styleURL: URL
    public var centerLat: Double
    public var centerLon: Double
    public var puckLat: Double
    public var puckLon: Double
    /// GNSS YOU mark. Pack center may rest the camera, but it is never YOU.
    public var showYou: Bool
    public var packSouth: Double
    public var packWest: Double
    public var packNorth: Double
    public var packEast: Double
    public var route: [(lat: Double, lon: Double)]
    public var destination: (lat: Double, lon: Double)?
    /// The point the inspect card is about, marked so the card never hides it.
    public var held: (lat: Double, lon: Double)?
    /// Bumped by KHAN EYE. Every other value change leaves the camera where the thumb left it.
    public var fitToken: Int
    /// UIKit `MLNMapView` ignores SwiftUI `allowsHitTesting`. This is the
    /// value that has to live on the Metal view.
    public var interactive: Bool
    public var onMapTap: ((Double, Double) -> Void)?
    /// A thumb held still on a place, with whatever the pack has drawn there,
    /// and the zoom so the water index can claim the same ground the thumb covers.
    public var onMapHold: ((Double, Double, [String: String], Double) -> Void)?
    /// A thumb held still on YOU or a party emblem. Id is `YOU` or the peer.
    public var onPersonHold: ((String, Double, Double) -> Void)?
    /// Tap a coin in EYE. Walking MAP still uses empty-map dest taps.
    public var onPersonTap: ((String, Double, Double) -> Void)?
    /// Double-tap a coin in EYE: lock-follow that contact.
    public var onPersonDoubleTap: ((String, Double, Double) -> Void)?
    /// Double-tap empty ground in EYE: plant RALLY.
    public var onEmptyDoubleTap: ((Double, Double) -> Void)?
    /// Boot preview must not ask for GPS. The live MAP still does.
    public var trackUser: Bool
    public var pips: [PartyBody]
    /// Live heading on YOU. Nil until the compass has a reading.
    public var youHeading: Double?
    /// Face on YOU. Party faces arrive on each pip.
    public var youEmblem: String
    public var onPulse: (() -> Void)?
    /// LOCK-ON follows YOU. Off, the thumb owns the camera.
    public var lockOn: Bool
    /// KHAN EYE holds the pack in frame. Exclusive with LOCK-ON.
    public var godsEye: Bool
    /// WALK dashes the accent core. DRIVE keeps it solid. Chrome already
    /// says which; the line has to match.
    public var travelMode: TravelMode
    public var sun: Bool
    public var eyeLayers: [EyeDesk.Layer]
    public var eyePalette: EyeDesk.Palette
    public var followID: String?
    public var trails: [[(lat: Double, lon: Double)]]
    public var rings: [EyeDesk.Ring]
    public var frameExtra: [(lat: Double, lon: Double)]
    public var offAerial: Bool

    public init(
        styleURL: URL,
        centerLat: Double,
        centerLon: Double,
        puckLat: Double,
        puckLon: Double,
        showYou: Bool = true,
        packSouth: Double,
        packWest: Double,
        packNorth: Double,
        packEast: Double,
        route: [(lat: Double, lon: Double)] = [],
        destination: (lat: Double, lon: Double)? = nil,
        held: (lat: Double, lon: Double)? = nil,
        fitToken: Int = 0,
        trackUser: Bool = true,
        interactive: Bool = true,
        onMapTap: ((Double, Double) -> Void)? = nil,
        onMapHold: ((Double, Double, [String: String], Double) -> Void)? = nil,
        onPersonHold: ((String, Double, Double) -> Void)? = nil,
        onPersonTap: ((String, Double, Double) -> Void)? = nil,
        onPersonDoubleTap: ((String, Double, Double) -> Void)? = nil,
        onEmptyDoubleTap: ((Double, Double) -> Void)? = nil,
        pips: [PartyBody] = [],
        youHeading: Double? = nil,
        youEmblem: String = PersonEmblem.fallback.rawValue,
        onPulse: (() -> Void)? = nil,
            lockOn: Bool = false,
            godsEye: Bool = false,
            travelMode: TravelMode = .walk,
        sun: Bool = false,
        eyeLayers: [EyeDesk.Layer] = EyeDesk.Layer.allCases,
        eyePalette: EyeDesk.Palette = .streets,
        followID: String? = nil,
        trails: [[(lat: Double, lon: Double)]] = [],
        rings: [EyeDesk.Ring] = [],
        frameExtra: [(lat: Double, lon: Double)] = [],
        offAerial: Bool = false
    ) {
        self.styleURL = styleURL
        self.centerLat = centerLat
        self.centerLon = centerLon
        self.puckLat = puckLat
        self.puckLon = puckLon
        self.showYou = showYou
        self.packSouth = packSouth
        self.packWest = packWest
        self.packNorth = packNorth
        self.packEast = packEast
        self.route = route
        self.destination = destination
        self.held = held
        self.fitToken = fitToken
        self.trackUser = trackUser
        self.interactive = interactive
        self.onMapTap = onMapTap
        self.onMapHold = onMapHold
        self.onPersonHold = onPersonHold
        self.onPersonTap = onPersonTap
        self.onPersonDoubleTap = onPersonDoubleTap
        self.onEmptyDoubleTap = onEmptyDoubleTap
        self.pips = pips
        self.youHeading = youHeading
        self.youEmblem = youEmblem
        self.onPulse = onPulse
        self.lockOn = lockOn
        self.godsEye = godsEye
        self.travelMode = travelMode
        self.sun = sun
        self.eyeLayers = eyeLayers
        self.eyePalette = eyePalette
        self.followID = followID
        self.trails = trails
        self.rings = rings
        self.frameExtra = frameExtra
        self.offAerial = offAerial
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> MLNMapView {
        let view = FillingMapView(frame: .zero, styleURL: styleURL)
        view.delegate = context.coordinator
        view.onBoundsChange = { [weak view] size in
            guard let view, let spec = context.coordinator.spec else { return }
            context.coordinator.applyCamera(spec, on: view, force: false)
            _ = size
        }
        applyInteraction(view)
        view.prefetchesTiles = false
        view.shouldRequestAuthorizationToUseLocationServices = trackUser
        view.showsUserLocation = trackUser
        view.backgroundColor = PackStyle.canvasColor(sun: false)
        let home = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        if CLLocationCoordinate2DIsValid(home) {
            view.setCenter(
                home,
                zoomLevel: PackCamera.openZoom,
                direction: PackCamera.godsEyeHeading,
                animated: false
            )
            let cam = view.camera
            cam.pitch = CGFloat(PackCamera.holdPitch(godsEye: godsEye))
            cam.heading = PackCamera.godsEyeHeading
            view.camera = cam
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        view.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
        let hold = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleHold(_:))
        )
        hold.minimumPressDuration = Inspect.holdSeconds
        // A thumb that travels further than this was panning, so the hold
        // fails and MapLibre keeps the drag.
        hold.allowableMovement = CGFloat(Inspect.holdDriftPoints)
        hold.delegate = context.coordinator
        view.addGestureRecognizer(hold)
        // A tap that lands inside a hold would fire on lift and move the
        // destination out from under the card.
        tap.require(toFail: hold)
        context.coordinator.onMapTap = onMapTap
        context.coordinator.onMapHold = onMapHold
        context.coordinator.onPersonHold = onPersonHold
        context.coordinator.onPersonTap = onPersonTap
        context.coordinator.onPersonDoubleTap = onPersonDoubleTap
        context.coordinator.onEmptyDoubleTap = onEmptyDoubleTap
        context.coordinator.onPulse = onPulse
        context.coordinator.trackUser = trackUser
        context.coordinator.interactive = interactive
        context.coordinator.apply(overlaySpec, on: view, force: true)
        return view
    }

    public func updateUIView(_ uiView: MLNMapView, context: Context) {
        if uiView.styleURL != styleURL {
            uiView.styleURL = styleURL
        }
        uiView.shouldRequestAuthorizationToUseLocationServices = trackUser
        uiView.showsUserLocation = trackUser
        applyInteraction(uiView)
        context.coordinator.onMapTap = onMapTap
        context.coordinator.onMapHold = onMapHold
        context.coordinator.onPersonHold = onPersonHold
        context.coordinator.onPersonTap = onPersonTap
        context.coordinator.onPersonDoubleTap = onPersonDoubleTap
        context.coordinator.onEmptyDoubleTap = onEmptyDoubleTap
        context.coordinator.onPulse = onPulse
        context.coordinator.trackUser = trackUser
        context.coordinator.interactive = interactive
        context.coordinator.apply(overlaySpec, on: uiView, force: false)
    }

    private func applyInteraction(_ view: MLNMapView) {
        view.isUserInteractionEnabled = interactive
        view.accessibilityElementsHidden = !interactive
        view.logoView.isHidden = true
        view.attributionButton.isHidden = true
        view.compassView.isHidden = true
        view.scaleBar.isHidden = true
        // Packed 3D neighborhood desk: pinch, pan, orbit, and tilt.
        view.allowsRotating = PackCamera.allowsOrbit(godsEye: godsEye)
        view.isScrollEnabled = PackCamera.allowsPan(godsEye: godsEye)
        view.allowsTilting = PackCamera.allowsTilt(godsEye: godsEye)
        view.minimumPitch = CGFloat(PackCamera.holdMinPitch(godsEye: godsEye))
        view.maximumPitch = CGFloat(PackCamera.holdMaxPitch(godsEye: godsEye))
        view.minimumZoomLevel = PackCamera.minZoom
        view.maximumZoomLevel = PackCamera.holdMaxZoom(godsEye: godsEye)
        if let map = view as? FillingMapView {
            map.setDeskChrome(godsEye: godsEye, offAerial: offAerial)
        }
        for rec in view.gestureRecognizers ?? [] {
            guard let tap = rec as? UITapGestureRecognizer, tap.numberOfTapsRequired == 2 else { continue }
            if tap.delegate is Coordinator {
                tap.isEnabled = godsEye
            } else if tap.delegate === nil {
                tap.isEnabled = !godsEye
            }
        }
    }

    private var overlaySpec: Coordinator.OverlaySpec {
        Coordinator.OverlaySpec(
            puckLat: puckLat,
            puckLon: puckLon,
            showYou: showYou,
            packSouth: packSouth,
            packWest: packWest,
            packNorth: packNorth,
            packEast: packEast,
            route: route,
            destination: destination,
            held: held,
            fitToken: fitToken,
            pips: pips,
            youHeading: youHeading,
            youEmblem: youEmblem,
            homeLat: centerLat,
            homeLon: centerLon,
            lockOn: lockOn,
            godsEye: godsEye,
            travelMode: travelMode,
            sun: sun,
            eyeLayers: eyeLayers,
            eyePalette: eyePalette,
            followID: followID,
            trails: trails,
            rings: rings,
            frameExtra: frameExtra,
            offAerial: offAerial
        )
    }

    public final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        struct OverlaySpec {
            var puckLat: Double
            var puckLon: Double
            var showYou: Bool
            var packSouth: Double
            var packWest: Double
            var packNorth: Double
            var packEast: Double
            var route: [(lat: Double, lon: Double)]
            var destination: (lat: Double, lon: Double)?
            var held: (lat: Double, lon: Double)?
            var fitToken: Int
            var pips: [PartyBody]
            var youHeading: Double?
            var youEmblem: String
            var homeLat: Double
            var homeLon: Double
            var lockOn: Bool
            var godsEye: Bool
            var travelMode: TravelMode
            var sun: Bool
            var eyeLayers: [EyeDesk.Layer]
            var eyePalette: EyeDesk.Palette
            var followID: String?
            var trails: [[(lat: Double, lon: Double)]]
            var rings: [EyeDesk.Ring]
            var frameExtra: [(lat: Double, lon: Double)]
            var offAerial: Bool
        }

        var spec: OverlaySpec?
        var onMapTap: ((Double, Double) -> Void)?
        var onMapHold: ((Double, Double, [String: String], Double) -> Void)?
        var onPersonHold: ((String, Double, Double) -> Void)?
        var onPersonTap: ((String, Double, Double) -> Void)?
        var onPersonDoubleTap: ((String, Double, Double) -> Void)?
        var onEmptyDoubleTap: ((Double, Double) -> Void)?
        var onPulse: (() -> Void)?
        var trackUser = true
        var interactive = true
        private let holdTick = UIImpactFeedbackGenerator(style: .rigid)
        var packOutline: MLNPolyline?
        var routeLine: MLNPolyline?
        var puck: MLNPointAnnotation?
        var partyMarks: [PersonMarkAnnotation] = []
        var storedPack: (south: Double, west: Double, north: Double, east: Double)?
        var storedPuck: (lat: Double, lon: Double)?
        var storedRoute: [(lat: Double, lon: Double)]?
        var storedDestination: (lat: Double, lon: Double)?
        var storedHeld: (lat: Double, lon: Double)?
        var storedPips: [PartyBody]?
        var fittedPack: (south: Double, west: Double, north: Double, east: Double)?
        var fittedSize: (width: Double, height: Double)?
        var fittedFitToken = 0
        var storedLockOn = false
        var storedGodsEye = false
        var followedPuck: (lat: Double, lon: Double)?
        var storedShowYou = false
        var storedMode: TravelMode?
        var storedSun = false
        var storedPalette: EyeDesk.Palette?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard interactive, gesture.state == .ended, let view = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: view)
            if spec?.godsEye == true, let mark = personMark(at: point, on: view) {
                guard CLLocationCoordinate2DIsValid(mark.coordinate) else { return }
                onPersonTap?(mark.memberID, mark.coordinate.latitude, mark.coordinate.longitude)
                onPulse?()
                return
            }
            if spec?.godsEye == true { return }
            let coord = view.convert(point, toCoordinateFrom: view)
            guard CLLocationCoordinate2DIsValid(coord) else { return }
            onMapTap?(coord.latitude, coord.longitude)
            onPulse?()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard interactive, gesture.state == .ended, let view = gesture.view as? MLNMapView else { return }
            guard spec?.godsEye == true else { return }
            let point = gesture.location(in: view)
            if let mark = personMark(at: point, on: view) {
                guard CLLocationCoordinate2DIsValid(mark.coordinate) else { return }
                onPersonDoubleTap?(mark.memberID, mark.coordinate.latitude, mark.coordinate.longitude)
                onPulse?()
                return
            }
            let coord = view.convert(point, toCoordinateFrom: view)
            guard CLLocationCoordinate2DIsValid(coord) else { return }
            onEmptyDoubleTap?(coord.latitude, coord.longitude)
            onPulse?()
        }

        @objc func handleHold(_ gesture: UILongPressGestureRecognizer) {
            guard interactive, gesture.state == .began, let view = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: view)
            if let mark = personMark(at: point, on: view) {
                guard CLLocationCoordinate2DIsValid(mark.coordinate) else { return }
                holdTick.impactOccurred()
                onPersonHold?(mark.memberID, mark.coordinate.latitude, mark.coordinate.longitude)
                onPulse?()
                if spec?.godsEye != true {
                    liftIntoView(point, on: view)
                }
                return
            }
            let coord = view.convert(point, toCoordinateFrom: view)
            guard CLLocationCoordinate2DIsValid(coord) else { return }
            holdTick.impactOccurred()
            onMapHold?(coord.latitude, coord.longitude, record(under: point, on: view), view.zoomLevel)
            onPulse?()
            if spec?.godsEye != true {
                liftIntoView(point, on: view)
            }
        }

        /// YOU and party emblems win over the ground record under the same thumb.
        func personMark(at: CGPoint, on view: MLNMapView) -> PersonMarkAnnotation? {
            var marks = partyMarks
            if let you = puck as? PersonMarkAnnotation {
                marks.append(you)
            }
            let reach = CGFloat(Inspect.holdProbePoints) / 2
            var hit: PersonMarkAnnotation?
            var best = CGFloat.greatestFiniteMagnitude
            for mark in marks {
                let screen = view.convert(mark.coordinate, toPointTo: view)
                let dx = screen.x - at.x
                let dy = screen.y - at.y
                let d = (dx * dx + dy * dy).squareRoot()
                if d <= reach, d < best {
                    best = d
                    hit = mark
                }
            }
            return hit
        }

        /// Slide the map so the held place is above the card instead of behind
        /// it. Capping the card at half the screen keeps the top half clear;
        /// this is what puts the pin up there when the thumb landed low.
        func liftIntoView(_ point: CGPoint, on view: MLNMapView) {
            let height = view.bounds.height
            guard height > 1, point.y > height * Inspect.holdLiftBelow else { return }
            let drop = point.y - height * Inspect.holdLiftTo
            let moved = view.convert(
                CGPoint(x: view.bounds.midX, y: view.bounds.midY + drop),
                toCoordinateFrom: view
            )
            guard CLLocationCoordinate2DIsValid(moved) else { return }
            view.setCenter(moved, animated: true)
        }

        /// What the pack recorded under the thumb.
        ///
        /// Painted layers are asked first — fills and lines come back that way.
        /// Points do not: a tank is a five-point circle, and MapLibre's own
        /// docs say `visibleFeatures` only returns what the style drew large
        /// enough to hit. So the same 44pt box is then asked of the pack's
        /// vector source, and any spring, well, tank or tap whose coordinate
        /// falls inside it is added to the ranking. Overlay sheets are the
        /// same problem as a faint fill: one percent opacity and walking-zoom
        /// minzoom are for the eye, not the record. The hold asks the
        /// geojson source whether the press sits in a glasshouse, cave
        /// preserve, wildlife range, botanic garden, or open reserve, so
        /// FIELD still names the book when the silver outline has not
        /// painted. The puck, the route and the pin are still skipped: they
        /// are the app talking to itself.
        func record(under point: CGPoint, on view: MLNMapView) -> [String: String] {
            guard let style = view.style else { return [:] }
            let readable = Set(
                style.layers
                    .map(\.identifier)
                    .filter { !Inspect.overlayLayerIDs.contains($0) }
            )
            let reach = CGFloat(Inspect.holdProbePoints)
            let box = CGRect(
                x: point.x - reach / 2,
                y: point.y - reach / 2,
                width: reach,
                height: reach
            )
            let painted = readable.isEmpty
                ? []
                : view.visibleFeatures(in: box, styleLayerIdentifiers: readable)
            let points = packPoints(in: box, on: view, style: style)
            let pressed = view.convert(
                CGPoint(x: box.midX, y: box.midY),
                toCoordinateFrom: view
            )
            let worked = packWorkedGround(at: pressed, style: style)
            return Inspect.pick((painted + points + worked).map(Self.tags(from:)))
        }

        /// Overlay sheets `visibleFeatures` will miss when the fill is too
        /// faint or the camera is below walking zoom. Restricted to the
        /// pack's ground geojson so a hold cannot read a pin. Exact press,
        /// not the 44pt box. Bbox-reject via overlayBounds before copying
        /// rings: NM is ~102 sheets / ~13k verts, and walking every ring on
        /// the HUD is the same stall class as ranking 34k packed names.
        private func packWorkedGround(
            at coordinate: CLLocationCoordinate2D,
            style: MLNStyle
        ) -> [MLNFeature] {
            guard CLLocationCoordinate2DIsValid(coordinate) else { return [] }
            guard let source = style.source(withIdentifier: PackStyle.groundWorkedSourceID)
                    as? MLNShapeSource
            else { return [] }
            return source.features(matching: nil).filter { feature in
                if let overlay = feature as? MLNOverlay,
                   !MLNCoordinateInCoordinateBounds(coordinate, overlay.overlayBounds) {
                    return false
                }
                return Self.covers(feature, coordinate)
            }
        }

        /// Whether the press sits in an overlay polygon. Holes are not the
        /// record. A point or a line is not a sheet.
        private static func covers(_ feature: MLNFeature, _ coordinate: CLLocationCoordinate2D) -> Bool {
            if let polygon = feature as? MLNPolygon {
                return covers(polygon, coordinate)
            }
            if let multi = feature as? MLNMultiPolygon {
                return multi.polygons.contains { covers($0, coordinate) }
            }
            return false
        }

        private static func covers(_ polygon: MLNPolygon, _ coordinate: CLLocationCoordinate2D) -> Bool {
            guard ringContains(polygon, coordinate) else { return false }
            if let holes = polygon.interiorPolygons {
                for hole in holes where ringContains(hole, coordinate) {
                    return false
                }
            }
            return true
        }

        private static func ringContains(
            _ polygon: MLNPolygon,
            _ coordinate: CLLocationCoordinate2D
        ) -> Bool {
            let count = Int(polygon.pointCount)
            guard count >= 3 else { return false }
            var ring = Array(
                repeating: kCLLocationCoordinate2DInvalid,
                count: count
            )
            polygon.getCoordinates(&ring, range: NSRange(location: 0, length: count))
            var inside = false
            var j = count - 1
            for i in 0..<count {
                let pi = ring[i]
                let pj = ring[j]
                let straddles = (pi.latitude > coordinate.latitude)
                    != (pj.latitude > coordinate.latitude)
                if straddles {
                    let at = (pj.longitude - pi.longitude)
                        * (coordinate.latitude - pi.latitude)
                        / (pj.latitude - pi.latitude)
                        + pi.longitude
                    if coordinate.longitude < at {
                        inside.toggle()
                    }
                }
                j = i
            }
            return inside
        }

        /// Points the style drew too small for `visibleFeatures` to admit.
        /// Restricted to the pack's own source so a hold cannot read a pin.
        private func packPoints(
            in box: CGRect,
            on view: MLNMapView,
            style: MLNStyle
        ) -> [MLNFeature] {
            guard let source = style.source(withIdentifier: Inspect.packSourceID) as? MLNVectorTileSource
            else { return [] }
            // `convert(_:toCoordinateBoundsFrom:)` has been seen to hand back
            // a north-west / south-east pair. The inline bounds test wants
            // south-west / north-east, and an inverted box drops every point.
            // The four corners, then min/max, cannot invert.
            let corners = [
                CGPoint(x: box.minX, y: box.minY),
                CGPoint(x: box.maxX, y: box.minY),
                CGPoint(x: box.minX, y: box.maxY),
                CGPoint(x: box.maxX, y: box.maxY),
            ].map { view.convert($0, toCoordinateFrom: view) }
            let south = corners.map(\.latitude).min() ?? 0
            let north = corners.map(\.latitude).max() ?? 0
            let west = corners.map(\.longitude).min() ?? 0
            let east = corners.map(\.longitude).max() ?? 0
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: south, longitude: west),
                ne: CLLocationCoordinate2D(latitude: north, longitude: east)
            )
            return source
                .features(sourceLayerIdentifiers: Inspect.packPointSourceLayers, predicate: nil)
                .filter { feature in
                    let tags = Self.tags(from: feature)
                    let isPoint = Inspect.packPointClasses.contains(tags["class"] ?? "")
                        || Inspect.packGroundPointNaturals.contains(tags["natural"] ?? "")
                        || ["storage_tank", "water_tank", "water_well", "cistern", "reservoir_covered"]
                        .contains(tags["man_made"] ?? "")
                    guard isPoint else { return false }
                    return MLNCoordinateInCoordinateBounds(feature.coordinate, bounds)
                }
        }

        private static func tags(from feature: MLNFeature) -> [String: String] {
            var tags: [String: String] = [:]
            for (key, value) in feature.attributes {
                if let text = value as? String {
                    tags[key] = text
                } else if let number = value as? NSNumber {
                    tags[key] = number.stringValue
                }
            }
            return tags
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // Touch-down is the 0.4s of notice the haptic engine wants. Cold,
            // the tick arrives after the card, and the whole point of it is to
            // say the card is coming.
            if gestureRecognizer is UILongPressGestureRecognizer { holdTick.prepare() }
            return true
        }

        func apply(_ spec: OverlaySpec, on view: MLNMapView, force: Bool) {
            self.spec = spec
            let lampFlip = storedSun != spec.sun
            let eyeFlip = storedGodsEye != spec.godsEye
            storedSun = spec.sun
            view.backgroundColor = PackStyle.canvasColor(sun: spec.sun)
            applyCamera(spec, on: view, force: force)
            let mapHasPuck = (view.annotations ?? []).contains { ann in
                ann.title == UserPuck.title
            }
            let puckNeeds = force
                || spec.showYou != mapHasPuck
                || UserPuck.needsReapply(
                    storedPack: storedPack,
                    storedPuck: storedPuck,
                    pack: (spec.packSouth, spec.packWest, spec.packNorth, spec.packEast),
                    puck: (spec.puckLat, spec.puckLon),
                    mapHasPuck: mapHasPuck || !spec.showYou
                )
            let routeNeeds = force || lampFlip || RouteLine.needsReapply(
                stored: storedRoute,
                route: spec.route,
                storedMode: storedMode,
                mode: spec.travelMode
            )
            let destNeeds = force || DestinationPin.needsReapply(
                stored: storedDestination,
                destination: spec.destination
            )
            // Both pins live in the same style pass, so either one moving is
            // reason enough to run it.
            let heldNeeds = force || HoldPin.needsReapply(stored: storedHeld, held: spec.held)
            let partyNeeds = force || PartyPips.needsReapply(stored: storedPips, pips: spec.pips)
            if OverlaySync.needsStyleMutation(
                force: force,
                puckNeedsReapply: puckNeeds,
                routeNeedsReapply: routeNeeds,
                destinationNeedsReapply: destNeeds || heldNeeds,
                partyNeedsReapply: partyNeeds
            ) {
                if !puckNeeds {
                    syncRoute(on: view, spec: spec, force: force)
                    syncStyleOverlays(on: view, spec: spec)
                    storedDestination = spec.destination
                    storedHeld = spec.held
                    storedPips = spec.pips
                    storedMode = spec.travelMode
                } else {
                    if let old = packOutline {
                        view.remove(old)
                    }
                    if let old = puck {
                        view.removeAnnotation(old)
                    }

                    var ring = PackGeometry.bboxRing(
                        south: spec.packSouth,
                        west: spec.packWest,
                        north: spec.packNorth,
                        east: spec.packEast
                    ).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    let outline = MLNPolyline(coordinates: &ring, count: UInt(ring.count))
                    view.add(outline)
                    packOutline = outline

                    if spec.showYou {
                        let you = PersonMarkAnnotation()
                        you.coordinate = CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon)
                        you.title = UserPuck.title
                        you.memberID = UserPuck.title
                        you.emblemID = spec.youEmblem
                        you.headingDeg = spec.youHeading
                        view.addAnnotation(you)
                        puck = you
                        storedPuck = (spec.puckLat, spec.puckLon)
                    } else {
                        puck = nil
                        storedPuck = nil
                    }
                    storedPack = (spec.packSouth, spec.packWest, spec.packNorth, spec.packEast)
                    syncRoute(on: view, spec: spec, force: true)
                    syncStyleOverlays(on: view, spec: spec)
                    storedDestination = spec.destination
                    storedHeld = spec.held
                    storedPips = spec.pips
                    storedMode = spec.travelMode
                }
            }
            syncPersonMarks(on: view, spec: spec)
            if let style = view.style {
                let paletteFlip = storedPalette != spec.eyePalette
                storedPalette = spec.eyePalette
                if force || lampFlip || paletteFlip || eyeFlip {
                    PackStyle.applyHUDLamp(style, sun: spec.sun)
                    PackStyle.applyEyePalette(style, godsEye: spec.godsEye, palette: spec.eyePalette)
                }
                PackStyle.applyEyeLayers(style, godsEye: spec.godsEye, layers: spec.eyeLayers)
                syncEyeOverlays(on: view, spec: spec)
            }
        }

        func syncPersonMarks(on view: MLNMapView, spec: OverlaySpec) {
            if !spec.showYou {
                if let old = puck {
                    view.removeAnnotation(old)
                    puck = nil
                }
                storedPuck = nil
            } else if let you = puck as? PersonMarkAnnotation {
                you.coordinate = CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon)
                you.emblemID = spec.youEmblem
                you.headingDeg = spec.youHeading
                storedPuck = (spec.puckLat, spec.puckLon)
                if let mark = view.view(for: you) as? YouPuckAnnotationView {
                    mark.apply(emblemID: spec.youEmblem, headingDeg: spec.youHeading)
                }
            }
            syncPartyMarks(on: view, spec: spec)
        }

        func syncPartyMarks(on view: MLNMapView, spec: OverlaySpec) {
            var existing: [String: PersonMarkAnnotation] = [:]
            existing.reserveCapacity(partyMarks.count)
            for mark in partyMarks {
                existing[mark.memberID] = mark
            }
            var next: [PersonMarkAnnotation] = []
            var seen = Set<String>()
            for pip in spec.pips {
                if spec.godsEye {
                    if PlaceMark.parse(pip.id) != nil {
                        if !EyeDesk.layerOn(.marks, in: spec.eyeLayers) { continue }
                    } else if !EyeDesk.layerOn(.party, in: spec.eyeLayers) {
                        continue
                    }
                }
                let coordinate = CLLocationCoordinate2D(latitude: pip.lat, longitude: pip.lon)
                guard CLLocationCoordinate2DIsValid(coordinate) else { continue }
                seen.insert(pip.id)
                if let old = existing[pip.id] {
                    stamp(old, pip: pip)
                    old.coordinate = coordinate
                    if let mark = view.view(for: old) as? YouPuckAnnotationView {
                        applyLook(mark, pip: pip)
                    }
                    next.append(old)
                } else {
                    let mark = PersonMarkAnnotation()
                    mark.coordinate = coordinate
                    mark.title = "\(PartyPips.titlePrefix)\(pip.id)"
                    stamp(mark, pip: pip)
                    view.addAnnotation(mark)
                    next.append(mark)
                }
            }
            for old in partyMarks where !seen.contains(old.memberID) {
                view.removeAnnotation(old)
            }
            partyMarks = next
            storedPips = spec.pips
        }

        func stamp(_ mark: PersonMarkAnnotation, pip: PartyBody) {
            mark.memberID = pip.id
            mark.emblemID = pip.emblem
            mark.headingDeg = pip.ghost ? nil : pip.headingDeg
            mark.condition = pip.condition
            mark.ghost = pip.ghost
            mark.lead = pip.lead
            mark.kid = pip.kid
            mark.overdue = pip.overdue
            mark.markKind = pip.markKind
            mark.badge = pip.markKind.isEmpty
                ? (pip.ageTitle.isEmpty ? pip.ageLabel : pip.ageTitle)
                : pip.markKind
        }

        func applyLook(_ view: YouPuckAnnotationView, pip: PartyBody) {
            let place = PlaceMark.parse(pip.id) != nil
            view.apply(
                emblemID: pip.emblem,
                headingDeg: pip.ghost ? nil : pip.headingDeg,
                tint: EyeLook.tint(pip.condition),
                ghost: pip.ghost,
                scale: CGFloat(place ? 0.78 : EyeDesk.leadScale(isLead: pip.lead)),
                badge: place
                    ? (pip.markKind.isEmpty ? "MARK" : pip.markKind)
                    : (pip.ageTitle.isEmpty ? pip.ageLabel : pip.ageTitle),
                kid: pip.kid,
                overdue: pip.overdue,
                place: place
            )
        }

        func syncEyeOverlays(on view: MLNMapView, spec: OverlaySpec) {
            guard let style = view.style else { return }
            let showTails = spec.godsEye && EyeDesk.layerOn(.tails, in: spec.eyeLayers)
            let tailShape: MLNShape
            if showTails, !spec.trails.isEmpty {
                let features: [[String: Any]] = spec.trails.compactMap { line in
                    guard line.count >= 2 else { return nil }
                    return [
                        "type": "Feature",
                        "geometry": [
                            "type": "LineString",
                            "coordinates": line.map { [$0.lon, $0.lat] },
                        ],
                    ]
                }
                let blob: [String: Any] = ["type": "FeatureCollection", "features": features]
                if let data = try? JSONSerialization.data(withJSONObject: blob),
                   let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
                {
                    tailShape = shape
                } else {
                    tailShape = emptyOverlayShape()
                }
            } else {
                tailShape = emptyOverlayShape()
            }
            if let src = style.source(withIdentifier: "eye-tails-src") as? MLNShapeSource {
                src.shape = tailShape
            } else {
                let src = MLNShapeSource(identifier: "eye-tails-src", shape: tailShape, options: nil)
                style.addSource(src)
                let layer = MLNLineStyleLayer(identifier: EyeDesk.tailsLayerID, source: src)
                layer.lineColor = NSExpression(
                    forConstantValue: UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.72)
                )
                layer.lineWidth = NSExpression(forConstantValue: 2)
                style.addLayer(layer)
            }

            var ringFeatures: [[String: Any]] = []
            if spec.godsEye {
                for ring in spec.rings {
                    let pts = EyeDesk.ringPoints(lat: ring.lat, lon: ring.lon, meters: ring.meters)
                    guard pts.count >= 8 else { continue }
                    ringFeatures.append([
                        "type": "Feature",
                        "properties": ["overdue": ring.overdue],
                        "geometry": [
                            "type": "LineString",
                            "coordinates": pts.map { [$0.lon, $0.lat] },
                        ],
                    ])
                }
            }
            let ringBlob: [String: Any] = ["type": "FeatureCollection", "features": ringFeatures]
            let ringShape: MLNShape
            if let data = try? JSONSerialization.data(withJSONObject: ringBlob),
               let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
            {
                ringShape = shape
            } else {
                ringShape = emptyOverlayShape()
            }
            if let src = style.source(withIdentifier: "eye-rings-src") as? MLNShapeSource {
                src.shape = ringShape
            } else {
                let src = MLNShapeSource(identifier: "eye-rings-src", shape: ringShape, options: nil)
                style.addSource(src)
                let layer = MLNLineStyleLayer(identifier: EyeDesk.ringsLayerID, source: src)
                layer.lineColor = NSExpression(
                    forConstantValue: UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 0.85)
                )
                layer.lineWidth = NSExpression(forConstantValue: 2)
                style.addLayer(layer)
            }
        }

        func syncRoute(on view: MLNMapView, spec: OverlaySpec, force: Bool) {
            if !force, !RouteLine.needsReapply(stored: storedRoute, route: spec.route) {
                return
            }
            if let old = routeLine {
                view.remove(old)
                routeLine = nil
            }
            if RouteLine.shouldDraw(spec.route) {
                var coords = spec.route.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                }
                let line = MLNPolyline(coordinates: &coords, count: UInt(coords.count))
                view.add(line)
                routeLine = line
            }
            storedRoute = spec.route
        }

        func applyCamera(_ spec: OverlaySpec, on view: MLNMapView, force: Bool) {
            guard view.bounds.width > 1, view.bounds.height > 1 else { return }
            defer {
                if !spec.godsEye {
                    let cam = view.camera
                    cam.pitch = CGFloat(PackCamera.holdPitch(godsEye: false))
                    if let heading = PackCamera.followHeading(
                        lockOn: spec.lockOn,
                        godsEye: spec.godsEye,
                        youHeading: spec.youHeading
                    ) {
                        cam.heading = heading
                    }
                    view.camera = cam
                }
            }
            let pack = (spec.packSouth, spec.packWest, spec.packNorth, spec.packEast)
            let size = (width: Double(view.bounds.width), height: Double(view.bounds.height))
            let puckCoord = CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon)
            let puckOK = spec.showYou && CLLocationCoordinate2DIsValid(puckCoord)
            let wasShowingYou = storedShowYou
            storedShowYou = spec.showYou
            if spec.fitToken != fittedFitToken {
                fittedFitToken = spec.fitToken
                if PackCamera.shouldHoldPack(godsEye: spec.godsEye) {
                    fitPack(spec, on: view, fly: true)
                    fittedPack = pack
                    fittedSize = size
                    storedLockOn = spec.lockOn
                    storedGodsEye = spec.godsEye
                    followedPuck = nil
                    return
                }
            }
            if PackCamera.shouldHoldPack(godsEye: spec.godsEye) {
                storedGodsEye = true
                storedLockOn = spec.lockOn
                followedPuck = nil
                if let follow = followCoordinate(spec) {
                    view.setCenter(follow, animated: !force)
                    fittedPack = pack
                    fittedSize = size
                    return
                }
                if force || PackCamera.shouldRefit(
                    fittedPack: fittedPack,
                    pack: pack,
                    fittedSize: fittedSize,
                    size: size
                ) {
                    fitPack(spec, on: view, fly: false)
                    fittedPack = pack
                    fittedSize = size
                }
                return
            }
            if PackCamera.shouldLeavePack(wasHolding: storedGodsEye, godsEye: spec.godsEye) {
                storedGodsEye = false
                let walkPitch = CGFloat(PackCamera.holdPitch(godsEye: false))
                if puckOK {
                    view.setCenter(
                        puckCoord,
                        zoomLevel: PackCamera.openZoom,
                        direction: PackCamera.godsEyeHeading,
                        animated: false
                    )
                } else {
                    let home = CLLocationCoordinate2D(latitude: spec.homeLat, longitude: spec.homeLon)
                    if CLLocationCoordinate2DIsValid(home) {
                        view.setCenter(
                            home,
                            zoomLevel: PackCamera.openZoom,
                            direction: PackCamera.godsEyeHeading,
                            animated: false
                        )
                    }
                }
                let cam = view.camera
                cam.pitch = walkPitch
                cam.heading = PackCamera.godsEyeHeading
                view.setCamera(cam, animated: false)
                fittedPack = pack
                fittedSize = size
                storedLockOn = spec.lockOn
                followedPuck = spec.lockOn && puckOK ? (spec.puckLat, spec.puckLon) : nil
                return
            }
            if PackCamera.shouldFitRoute(
                lockOn: spec.lockOn,
                stored: storedRoute,
                route: spec.route,
                godsEye: spec.godsEye
            ) {
                fitRoute(spec, on: view)
                fittedPack = pack
                fittedSize = size
                storedLockOn = spec.lockOn
                followedPuck = spec.lockOn && puckOK ? (spec.puckLat, spec.puckLon) : nil
                return
            }
            if puckOK, PackCamera.shouldFollow(
                lockOn: PackCamera.liveLockOn(lockOn: spec.lockOn, godsEye: spec.godsEye),
                wasLocked: storedLockOn,
                lastFollow: followedPuck,
                puck: (spec.puckLat, spec.puckLon),
                godsEye: spec.godsEye
            ) {
                if !storedLockOn {
                    view.setCenter(
                        puckCoord,
                        zoomLevel: PackCamera.openZoom,
                        animated: false
                    )
                } else {
                    view.setCenter(puckCoord, animated: true)
                }
                followedPuck = (spec.puckLat, spec.puckLon)
            }
            storedLockOn = spec.lockOn
            if !spec.lockOn {
                followedPuck = nil
            }
            if spec.lockOn {
                if puckOK, force || PackCamera.shouldRefit(
                    fittedPack: fittedPack,
                    pack: pack,
                    fittedSize: fittedSize,
                    size: size
                ) {
                    view.setCenter(puckCoord, animated: false)
                    fittedPack = pack
                    fittedSize = size
                }
                return
            }
            if let dest = spec.destination {
                let destCoord = CLLocationCoordinate2D(latitude: dest.lat, longitude: dest.lon)
                if CLLocationCoordinate2DIsValid(destCoord) {
                    let point = view.convert(destCoord, toPointTo: view)
                    if PackCamera.shouldFrameDest(
                        lockOn: spec.lockOn,
                        destChanged: DestinationPin.needsReapply(
                            stored: storedDestination,
                            destination: spec.destination
                        ),
                        destVisible: PackCamera.destIsOnGlass(
                            x: Double(point.x),
                            y: Double(point.y),
                            width: Double(view.bounds.width),
                            height: Double(view.bounds.height)
                        ),
                        godsEye: spec.godsEye
                    ) {
                        view.setCenter(
                            destCoord,
                            zoomLevel: view.zoomLevel,
                            animated: !force
                        )
                        fittedPack = pack
                        fittedSize = size
                        return
                    }
                }
            }
            if PackCamera.shouldOpenOnYou(
                showYou: spec.showYou,
                wasShowingYou: wasShowingYou,
                hasDest: spec.destination != nil,
                godsEye: spec.godsEye
            ), puckOK {
                view.setCenter(
                    puckCoord,
                    zoomLevel: PackCamera.openZoom,
                    animated: false
                )
                fittedPack = pack
                fittedSize = size
                return
            }
            if !force, !PackCamera.shouldRefit(
                fittedPack: fittedPack,
                pack: pack,
                fittedSize: fittedSize,
                size: size
            ) { return }
            guard puckOK else { return }
            view.setCenter(
                puckCoord,
                zoomLevel: PackCamera.openZoom,
                animated: false
            )
            fittedPack = pack
            fittedSize = size
        }

        func followCoordinate(_ spec: OverlaySpec) -> CLLocationCoordinate2D? {
            guard let follow = spec.followID, !follow.isEmpty else { return nil }
            if follow == UserPuck.title {
                let coord = CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon)
                return CLLocationCoordinate2DIsValid(coord) ? coord : nil
            }
            guard let pip = spec.pips.first(where: { $0.id == follow }) else { return nil }
            let coord = CLLocationCoordinate2D(latitude: pip.lat, longitude: pip.lon)
            return CLLocationCoordinate2DIsValid(coord) ? coord : nil
        }

        func fitPack(_ spec: OverlaySpec, on view: MLNMapView, fly _: Bool) {
            let packBox = PackCamera.bounds(
                south: spec.packSouth,
                west: spec.packWest,
                north: spec.packNorth,
                east: spec.packEast
            )
            let you = spec.showYou ? (lat: spec.puckLat, lon: spec.puckLon) : nil
            let points: [(lat: Double, lon: Double)]
            if let follow = followCoordinate(spec) {
                points = EyeDesk.framePoints(
                    you: (follow.latitude, follow.longitude),
                    party: [],
                    marks: [],
                    water: []
                )
            } else {
                let party = spec.pips.filter { PlaceMark.parse($0.id) == nil }.map { ($0.lat, $0.lon) }
                let marks = spec.pips.filter { PlaceMark.parse($0.id) != nil }.map { ($0.lat, $0.lon) }
                points = EyeDesk.framePoints(
                    you: you,
                    party: party,
                    marks: marks,
                    water: spec.frameExtra
                )
            }
            let desk = EyeDesk.bounds(points: points) ?? packBox
            let box = EyeDesk.clampToPack(desk: desk, pack: packBox)
            let mid = PackCamera.packCenter(
                south: box.south,
                west: box.west,
                north: box.north,
                east: box.east
            )
            let gev = PackCamera.godsEyeDistance(
                radiusMeters: PackCamera.packRadiusMeters(
                    south: box.south,
                    west: box.west,
                    north: box.north,
                    east: box.east
                )
            )
            // Pitch 45 + fitting the desk bounds + HUD padding pulls MapLibre
            // to pack scale (Hatch to Tularosa). Look at the desk mid at gev.
            let camera = MLNMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: mid.lat, longitude: mid.lon),
                acrossDistance: gev,
                pitch: CGFloat(PackCamera.godsEyePitch),
                heading: PackCamera.godsEyeHeading
            )
            view.setCamera(camera, animated: false)
        }

        func fitRoute(_ spec: OverlaySpec, on view: MLNMapView) {
            let lats = spec.route.map(\.lat)
            let lons = spec.route.map(\.lon)
            guard var south = lats.min(), var north = lats.max(),
                  var west = lons.min(), var east = lons.max() else { return }
            if abs(north - south) < 1e-5 {
                south -= 0.0004
                north += 0.0004
            }
            if abs(east - west) < 1e-5 {
                west -= 0.0004
                east += 0.0004
            }
            let box = PackCamera.bounds(south: south, west: west, north: north, east: east)
            let bounds = MLNCoordinateBoundsMake(
                CLLocationCoordinate2D(latitude: box.south, longitude: box.west),
                CLLocationCoordinate2D(latitude: box.north, longitude: box.east)
            )
            let pad = CGFloat(PackCamera.routePaddingPoints)
            view.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: pad, left: 24, bottom: pad, right: 16),
                animated: true,
                completionHandler: nil
            )
        }

        func syncStyleOverlays(on view: MLNMapView, spec: OverlaySpec) {
            guard let style = view.style else { return }
            var ring = PackGeometry.bboxRing(
                south: spec.packSouth,
                west: spec.packWest,
                north: spec.packNorth,
                east: spec.packEast
            ).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            let line = MLNPolyline(coordinates: &ring, count: UInt(ring.count))
            if let src = style.source(withIdentifier: "pack-bbox-src") as? MLNShapeSource {
                src.shape = line
            } else {
                let src = MLNShapeSource(identifier: "pack-bbox-src", shape: line, options: nil)
                style.addSource(src)
                let layer = MLNLineStyleLayer(identifier: "pack-bbox-line", source: src)
                layer.lineColor = NSExpression(
                    forConstantValue: PackStyle.inkColor(PackStyle.silverInk)
                )
                layer.lineWidth = NSExpression(forConstantValue: 3)
                style.addLayer(layer)
            }

            let youShape: MLNShape
            if spec.showYou {
                let you = MLNPointFeature()
                you.coordinate = CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon)
                youShape = you
            } else {
                youShape = emptyOverlayShape()
            }
            if let src = style.source(withIdentifier: "you-puck-src") as? MLNShapeSource {
                src.shape = youShape
            } else {
                let src = MLNShapeSource(identifier: "you-puck-src", shape: youShape, options: nil)
                style.addSource(src)
                let halo = MLNCircleStyleLayer(identifier: "you-puck-halo", source: src)
                halo.circleColor = NSExpression(
                    forConstantValue: UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.32)
                )
                halo.circleRadius = NSExpression(forConstantValue: 22)
                halo.circleStrokeColor = NSExpression(
                    forConstantValue: UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
                )
                halo.circleStrokeWidth = NSExpression(forConstantValue: 0)
                halo.circleStrokeOpacity = NSExpression(forConstantValue: 0)
                halo.circleOpacity = NSExpression(forConstantValue: 0)
                style.addLayer(halo)
                let core = MLNCircleStyleLayer(identifier: "you-puck-core", source: src)
                core.circleColor = NSExpression(
                    forConstantValue: UIColor(red: 0, green: 0, blue: 0, alpha: 0)
                )
                core.circleRadius = NSExpression(forConstantValue: 8)
                core.circleStrokeWidth = NSExpression(forConstantValue: 0)
                core.circleStrokeOpacity = NSExpression(forConstantValue: 0)
                core.circleOpacity = NSExpression(forConstantValue: 0)
                style.addLayer(core)
            }

            if let dest = spec.destination {
                let destCoord = CLLocationCoordinate2D(latitude: dest.lat, longitude: dest.lon)
                if CLLocationCoordinate2DIsValid(destCoord) {
                    let pin = MLNPointFeature()
                    pin.coordinate = destCoord
                    if let src = style.source(withIdentifier: DestinationPin.sourceID) as? MLNShapeSource {
                        src.shape = pin
                    } else {
                        let src = MLNShapeSource(identifier: DestinationPin.sourceID, shape: pin, options: nil)
                        style.addSource(src)
                        let ring = MLNCircleStyleLayer(identifier: DestinationPin.ringLayerID, source: src)
                        ring.circleColor = NSExpression(forConstantValue: UIColor.clear)
                        ring.circleRadius = NSExpression(forConstantValue: DestinationPin.ringRadius)
                        ring.circleStrokeColor = NSExpression(
                            forConstantValue: UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
                        )
                        ring.circleStrokeWidth = NSExpression(forConstantValue: 3)
                        style.addLayer(ring)
                        let core = MLNCircleStyleLayer(identifier: DestinationPin.coreLayerID, source: src)
                        core.circleColor = NSExpression(
                            forConstantValue: UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
                        )
                        core.circleRadius = NSExpression(forConstantValue: DestinationPin.coreRadius)
                        core.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                        core.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
                        style.addLayer(core)
                    }
                } else if let src = style.source(withIdentifier: DestinationPin.sourceID) as? MLNShapeSource {
                    src.shape = emptyOverlayShape()
                }
            } else if let src = style.source(withIdentifier: DestinationPin.sourceID) as? MLNShapeSource {
                src.shape = emptyOverlayShape()
            }

            if let point = spec.held {
                let heldCoord = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
                if CLLocationCoordinate2DIsValid(heldCoord) {
                    let mark = MLNPointFeature()
                    mark.coordinate = heldCoord
                    if let src = style.source(withIdentifier: HoldPin.sourceID) as? MLNShapeSource {
                        src.shape = mark
                    } else {
                        let src = MLNShapeSource(identifier: HoldPin.sourceID, shape: mark, options: nil)
                        style.addSource(src)
                        let ring = MLNCircleStyleLayer(identifier: HoldPin.ringLayerID, source: src)
                        ring.circleColor = NSExpression(
                            forConstantValue: UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.18)
                        )
                        ring.circleRadius = NSExpression(forConstantValue: HoldPin.ringRadius)
                        ring.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                        ring.circleStrokeWidth = NSExpression(forConstantValue: 2)
                        style.addLayer(ring)
                        let core = MLNCircleStyleLayer(identifier: HoldPin.coreLayerID, source: src)
                        core.circleColor = NSExpression(
                            forConstantValue: UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
                        )
                        core.circleRadius = NSExpression(forConstantValue: HoldPin.coreRadius)
                        core.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                        core.circleStrokeWidth = NSExpression(forConstantValue: 2)
                        style.addLayer(core)
                    }
                } else if let src = style.source(withIdentifier: HoldPin.sourceID) as? MLNShapeSource {
                    src.shape = emptyOverlayShape()
                }
            } else if let src = style.source(withIdentifier: HoldPin.sourceID) as? MLNShapeSource {
                src.shape = emptyOverlayShape()
            }

            if RouteLine.shouldDraw(spec.route) {
                var coords = spec.route.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                }
                let line = MLNPolyline(coordinates: &coords, count: UInt(coords.count))
                if let src = style.source(withIdentifier: RouteLine.sourceID) as? MLNShapeSource {
                    src.shape = line
                    paintRoute(on: style, source: src, mode: spec.travelMode, sun: spec.sun)
                } else {
                    let src = MLNShapeSource(identifier: RouteLine.sourceID, shape: line, options: nil)
                    style.addSource(src)
                    paintRoute(on: style, source: src, mode: spec.travelMode, sun: spec.sun)
                }
            } else if let src = style.source(withIdentifier: RouteLine.sourceID) as? MLNShapeSource {
                src.shape = emptyOverlayShape()
            }

            let party = partyShape(spec.pips)
            if let src = style.source(withIdentifier: PartyPips.sourceID) as? MLNShapeSource {
                src.shape = party
            } else {
                let src = MLNShapeSource(identifier: PartyPips.sourceID, shape: party, options: nil)
                style.addSource(src)
                let halo = MLNCircleStyleLayer(identifier: PartyPips.haloLayerID, source: src)
                halo.circleColor = NSExpression(
                    forConstantValue: UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.28)
                )
                halo.circleRadius = NSExpression(forConstantValue: PartyPips.haloRadius)
                halo.circleStrokeWidth = NSExpression(forConstantValue: 0)
                halo.circleStrokeOpacity = NSExpression(forConstantValue: 0)
                halo.circleOpacity = NSExpression(forConstantValue: 0)
                style.addLayer(halo)
                let core = MLNCircleStyleLayer(identifier: PartyPips.coreLayerID, source: src)
                core.circleColor = NSExpression(
                    forConstantValue: UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 1)
                )
                core.circleRadius = NSExpression(forConstantValue: PartyPips.coreRadius)
                core.circleStrokeColor = NSExpression(forConstantValue: UIColor.black)
                core.circleStrokeWidth = NSExpression(forConstantValue: 0)
                core.circleStrokeOpacity = NSExpression(forConstantValue: 0)
                core.circleOpacity = NSExpression(forConstantValue: 0)
                style.addLayer(core)
            }
        }

        /// Void casing, silver fill, scarce accent core. Streets at walking zoom
        /// are silver with a void or red casing; a single silver stroke of the
        /// same width disappears into them. WALK dashes only the core so the
        /// path never reads as another arterial; DRIVE stays a solid thread.
        func paintRoute(on style: MLNStyle, source: MLNSource, mode: TravelMode, sun: Bool) {
            let silver = PackStyle.inkColor(sun ? PackStyle.sunInkHex : PackStyle.silverInk)
            let accent = PackStyle.inkColor(PackStyle.accentInk)
            let casingInk = PackStyle.inkColor(PackStyle.voidInk)
            let round = NSExpression(forConstantValue: "round")

            func stroke(
                _ layer: MLNLineStyleLayer,
                color: UIColor,
                width: Double,
                dashed: Bool
            ) {
                layer.lineColor = NSExpression(forConstantValue: color)
                layer.lineWidth = NSExpression(forConstantValue: width)
                layer.lineCap = round
                layer.lineJoin = round
                if dashed, let dash = RouteLine.dashPattern(mode) {
                    layer.lineDashPattern = NSExpression(forConstantValue: dash)
                } else {
                    layer.lineDashPattern = nil
                }
            }

            let casing: MLNLineStyleLayer
            if let existing = style.layer(withIdentifier: RouteLine.casingLayerID) as? MLNLineStyleLayer {
                casing = existing
            } else {
                let layer = MLNLineStyleLayer(identifier: RouteLine.casingLayerID, source: source)
                if let fill = style.layer(withIdentifier: RouteLine.layerID) {
                    style.insertLayer(layer, below: fill)
                } else {
                    style.addLayer(layer)
                }
                casing = layer
            }
            stroke(casing, color: casingInk, width: RouteLine.casingWidth, dashed: false)

            let fill: MLNLineStyleLayer
            if let existing = style.layer(withIdentifier: RouteLine.layerID) as? MLNLineStyleLayer {
                fill = existing
            } else {
                let layer = MLNLineStyleLayer(identifier: RouteLine.layerID, source: source)
                style.addLayer(layer)
                fill = layer
            }
            stroke(fill, color: silver, width: RouteLine.fillWidth, dashed: false)

            let core: MLNLineStyleLayer
            if let existing = style.layer(withIdentifier: RouteLine.coreLayerID) as? MLNLineStyleLayer {
                core = existing
            } else {
                let layer = MLNLineStyleLayer(identifier: RouteLine.coreLayerID, source: source)
                style.addLayer(layer)
                core = layer
            }
            stroke(core, color: accent, width: RouteLine.coreWidth, dashed: true)
        }

        /// Silver bodies. MapLibre's Swift overlay does not import the ObjC
        /// collection factory. A FeatureCollection is the documented many-point source.
        func partyShape(_ pips: [PartyBody]) -> MLNShape {
            let features: [[String: Any]] = pips.compactMap { pip in
                let coordinate = CLLocationCoordinate2D(latitude: pip.lat, longitude: pip.lon)
                guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
                return [
                    "type": "Feature",
                    "properties": [:] as [String: Any],
                    "geometry": [
                        "type": "Point",
                        "coordinates": [pip.lon, pip.lat],
                    ] as [String: Any],
                ]
            }
            let geo: [String: Any] = [
                "type": "FeatureCollection",
                "features": features,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: geo),
               let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) {
                return shape
            }
            return coincidentLine()
        }

        /// Empty FeatureCollection. Never a 0-vertex polyline — MapLibre
        /// Native can crash when a 0-count `MLNPolyline` is assigned during
        /// LOCK-ON `setCenter` / WALK (same class as tearing YOU down on GPS
        /// ticks). Closing a Hold, OFF GRAPH, pack switch, and a failed
        /// party JSON all used to take that path.
        func emptyOverlayShape() -> MLNShape {
            partyShape([])
        }

        /// Last resort if FeatureCollection JSON fails. Two vertices. Never count 0.
        func coincidentLine() -> MLNShape {
            var coords = [
                CLLocationCoordinate2D(latitude: 0, longitude: 0),
                CLLocationCoordinate2D(latitude: 0, longitude: 0),
            ]
            return MLNPolyline(coordinates: &coords, count: 2)
        }

        public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            mapView.shouldRequestAuthorizationToUseLocationServices = trackUser
            mapView.showsUserLocation = trackUser
            fittedPack = nil
            fittedSize = nil
            if let spec {
                apply(spec, on: mapView, force: true)
            }
        }

        public func mapView(
            _ mapView: MLNMapView,
            regionIsChangingWith reason: MLNCameraChangeReason
        ) {
            if reason.contains(.gesturePan)
                || reason.contains(.gesturePinch)
                || reason.contains(.gestureRotate)
                || reason.contains(.gestureTilt)
                || reason.contains(.gestureZoomIn)
                || reason.contains(.gestureZoomOut)
                || reason.contains(.gestureOneFingerZoom)
            {
                onPulse?()
            }
        }

        public func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            _ = mapView
            onPulse?()
        }

        public func mapView(
            _ mapView: MLNMapView,
            shouldChangeFrom oldCamera: MLNMapCamera,
            to newCamera: MLNMapCamera
        ) -> Bool {
            _ = mapView
            _ = oldCamera
            guard let spec else { return true }
            return PackCamera.cameraStaysOnPack(
                godsEye: spec.godsEye,
                lat: newCamera.centerCoordinate.latitude,
                lon: newCamera.centerCoordinate.longitude,
                south: spec.packSouth,
                west: spec.packWest,
                north: spec.packNorth,
                east: spec.packEast
            )
        }

        public func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if annotation is MLNUserLocation {
                let reuse = "hidden-user-location"
                let hidden = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? HiddenUserLocationView)
                    ?? HiddenUserLocationView(reuseIdentifier: reuse)
                hidden.isHidden = true
                hidden.alpha = 0
                hidden.isEnabled = false
                hidden.isUserInteractionEnabled = false
                hidden.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
                return hidden
            }
            let you = annotation.title == UserPuck.title
            let place = PlaceMark.parse(((annotation as? PersonMarkAnnotation)?.memberID) ?? (annotation.title ?? "")) != nil
            let reuse = you ? "you-puck" : (place ? "place-pin" : "party-puck")
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? YouPuckAnnotationView)
                ?? YouPuckAnnotationView(reuseIdentifier: reuse)
            if let mark = annotation as? PersonMarkAnnotation {
                view.apply(
                    emblemID: mark.emblemID,
                    headingDeg: mark.headingDeg,
                    tint: EyeLook.tint(mark.condition),
                    ghost: mark.ghost,
                    scale: CGFloat(place ? 0.78 : EyeDesk.leadScale(isLead: mark.lead)),
                    badge: place ? (mark.markKind.isEmpty ? "MARK" : mark.markKind) : mark.badge,
                    kid: mark.kid,
                    overdue: mark.overdue,
                    place: place
                )
            } else if you {
                view.apply(emblemID: spec?.youEmblem, headingDeg: spec?.youHeading)
            }
            return view
        }

        public func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            _ = mapView
            _ = annotation
            return false
        }

        public func mapView(styleForDefaultUserLocationAnnotationView mapView: MLNMapView) -> MLNUserLocationAnnotationViewStyle {
            _ = mapView
            let style = MLNUserLocationAnnotationViewStyle()
            let clear = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
            style.puckFillColor = clear
            style.puckShadowColor = clear
            style.puckShadowOpacity = 0
            style.puckArrowFillColor = clear
            style.haloFillColor = clear
            return style
        }

        public func mapView(_ mapView: MLNMapView, fillColorForPolygonAnnotation annotation: MLNPolygon) -> UIColor {
            _ = mapView
            _ = annotation
            return UIColor(red: 0, green: 0, blue: 0, alpha: 0)
        }

        public func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if annotation === routeLine {
                return UIColor(red: 0, green: 0, blue: 0, alpha: 0)
            }
            return PackStyle.inkColor(spec?.sun == true ? PackStyle.sunInkHex : PackStyle.silverInk)
        }

        public func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat {
            1
        }

        public func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            if annotation === routeLine { return RouteLine.annotationWidth }
            return annotation === packOutline ? 3.5 : 2
        }
    }
}

final class FillingMapView: MLNMapView {
    var onBoundsChange: ((CGSize) -> Void)?
    private let osmCredit = UILabel()
    private let packStamp = UILabel()
    private let aerialStamp = UILabel()
    private var deskReady = false

    override func layoutSubviews() {
        super.layoutSubviews()
        installDeskChromeIfNeeded()
        layoutDeskChrome()
        onBoundsChange?(bounds.size)
    }

    func setDeskChrome(godsEye: Bool, offAerial: Bool) {
        installDeskChromeIfNeeded()
        osmCredit.isHidden = !godsEye
        packStamp.isHidden = !godsEye
        aerialStamp.isHidden = !(godsEye && offAerial)
        layoutDeskChrome()
    }

    private func installDeskChromeIfNeeded() {
        guard !deskReady else { return }
        deskReady = true
        osmCredit.font = .systemFont(ofSize: 9, weight: .bold)
        osmCredit.textColor = UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.82)
        osmCredit.text = OSMCredit.line
        osmCredit.isHidden = true
        addSubview(osmCredit)
        packStamp.font = .systemFont(ofSize: 9, weight: .heavy)
        packStamp.textColor = UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.82)
        packStamp.text = EyeDesk.packStamp
        packStamp.isHidden = true
        addSubview(packStamp)
        aerialStamp.font = .systemFont(ofSize: 11, weight: .heavy)
        aerialStamp.textColor = UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.92)
        aerialStamp.text = EyeDesk.offAerial
        aerialStamp.isHidden = true
        addSubview(aerialStamp)
    }

    private func layoutDeskChrome() {
        osmCredit.sizeToFit()
        packStamp.sizeToFit()
        aerialStamp.sizeToFit()
        let left = bounds.minX + 12
        let bottom = bounds.maxY - 96
        osmCredit.frame.origin = CGPoint(x: left, y: bottom - osmCredit.bounds.height)
        packStamp.frame.origin = CGPoint(x: left + osmCredit.bounds.width + 8, y: osmCredit.frame.minY)
        aerialStamp.frame.origin = CGPoint(
            x: bounds.midX - aerialStamp.bounds.width / 2,
            y: bounds.minY + 88
        )
    }
}

final class HiddenUserLocationView: MLNUserLocationAnnotationView {
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        hidePuck()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        hidePuck()
    }

    override func update() {
        super.update()
        hidePuck()
    }

    private func hidePuck() {
        isHidden = true
        alpha = 0
        isEnabled = false
        isUserInteractionEnabled = false
        scalesWithViewingDistance = false
        bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
    }
}

final class PersonMarkAnnotation: MLNPointAnnotation {
    var memberID = ""
    var emblemID: String?
    var headingDeg: Double?
    var condition = "green"
    var ghost = false
    var lead = false
    var kid = false
    var overdue = false
    var badge = ""
    var markKind = ""
}

final class YouPuckAnnotationView: MLNAnnotationView {
    private let rose = UIImageView()
    private let emblemView = UIImageView()
    private let pinView = UIImageView()
    private let headingView = UIView()
    private let chevronLayer = CAShapeLayer()
    private let badgeLabel = UILabel()
    private let kidDot = UIView()
    private let pulseLayer = CALayer()
    private var lastHeading: Double?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        let size = CGFloat(PersonCompass.puckPoints)
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        backgroundColor = .clear
        isOpaque = false
        isEnabled = false
        isUserInteractionEnabled = false
        scalesWithViewingDistance = false
        rotatesToMatchCamera = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.72
        layer.shadowRadius = 3.5
        layer.shadowOffset = .zero

        rose.frame = bounds
        rose.image = PersonCompassArt.rose
        rose.contentMode = .scaleAspectFit
        addSubview(rose)

        let well = CGFloat(PersonCompass.wellPoints)
        emblemView.frame = CGRect(
            x: (size - well) / 2,
            y: (size - well) / 2,
            width: well,
            height: well
        )
        emblemView.contentMode = .scaleAspectFill
        emblemView.clipsToBounds = true
        emblemView.layer.cornerRadius = well / 2
        emblemView.layer.borderWidth = 1
        emblemView.layer.borderColor = UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.55).cgColor
        addSubview(emblemView)

        pinView.frame = bounds
        pinView.contentMode = .scaleAspectFit
        pinView.isHidden = true
        addSubview(pinView)

        headingView.frame = bounds
        headingView.isUserInteractionEnabled = false
        headingView.backgroundColor = .clear
        headingView.isHidden = true
        addSubview(headingView)

        chevronLayer.fillColor = UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1).cgColor
        chevronLayer.strokeColor = UIColor.black.cgColor
        chevronLayer.lineWidth = 0.7
        chevronLayer.path = PersonCompassArt.chevronPath(in: bounds).cgPath
        headingView.layer.addSublayer(chevronLayer)

        pulseLayer.borderWidth = 0
        pulseLayer.opacity = 0
        layer.insertSublayer(pulseLayer, at: 0)

        badgeLabel.font = .systemFont(ofSize: 8, weight: .heavy)
        badgeLabel.textAlignment = .center
        badgeLabel.textColor = .white
        badgeLabel.isHidden = true
        addSubview(badgeLabel)

        kidDot.backgroundColor = UIColor(red: 46.0 / 255.0, green: 230.0 / 255.0, blue: 122.0 / 255.0, alpha: 1)
        kidDot.layer.cornerRadius = 4
        kidDot.isHidden = true
        addSubview(kidDot)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        lastHeading = nil
        headingView.isHidden = true
        headingView.layer.transform = CATransform3DIdentity
        emblemView.image = nil
        pinView.image = nil
        pinView.isHidden = true
        rose.isHidden = false
        emblemView.isHidden = false
        centerOffset = .zero
    }

    func apply(
        emblemID: String?,
        headingDeg: Double?,
        tint: UIColor? = nil,
        ghost: Bool = false,
        scale: CGFloat = 1,
        badge: String = "",
        kid: Bool = false,
        overdue: Bool = false,
        place: Bool = false
    ) {
        rose.isHidden = place
        emblemView.isHidden = place
        pinView.isHidden = !place
        let emblem = PersonEmblem.resolved(emblemID)
        emblemView.image = place ? nil : (PersonEmblem.image(emblem) ?? PersonEmblem.image(.fallback))
        let ink = tint ?? UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 1)
        emblemView.layer.borderColor = ink.cgColor
        alpha = ghost ? 0.42 : 1
        let size = CGFloat(PersonCompass.puckPoints) * max(scale, 0.7)
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        rose.frame = bounds
        pinView.frame = bounds
        headingView.frame = bounds
        if place {
            pinView.image = PersonCompassArt.pin(tint: ink)
            centerOffset = CGVector(dx: 0, dy: size / 2)
        } else {
            pinView.image = nil
            centerOffset = .zero
        }
        let well = CGFloat(PersonCompass.wellPoints) * max(scale, 0.7)
        emblemView.frame = CGRect(
            x: (size - well) / 2,
            y: (size - well) / 2,
            width: well,
            height: well
        )
        emblemView.layer.cornerRadius = well / 2
        if badge.isEmpty {
            badgeLabel.isHidden = true
        } else {
            badgeLabel.isHidden = false
            badgeLabel.text = badge
            badgeLabel.frame = CGRect(x: 0, y: size - 12, width: size, height: 12)
        }
        kidDot.isHidden = !kid
        kidDot.frame = CGRect(x: size - 10, y: 2, width: 8, height: 8)
        if overdue {
            if pulseLayer.animation(forKey: "overdue") == nil {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1
                pulse.toValue = 0.35
                pulse.duration = 0.7
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulseLayer.add(pulse, forKey: "overdue")
            }
        } else {
            pulseLayer.removeAnimation(forKey: "overdue")
            pulseLayer.opacity = 0
        }
        pulseLayer.frame = bounds
        pulseLayer.cornerRadius = size / 2
        pulseLayer.borderColor = UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1).cgColor
        pulseLayer.borderWidth = overdue ? 2 : 0
        if place {
            headingView.isHidden = true
            lastHeading = nil
            return
        }
        guard let headingDeg, headingDeg >= 0 else {
            headingView.isHidden = true
            lastHeading = nil
            return
        }
        headingView.isHidden = false
        let radians = PersonCompass.tickRadians(headingDeg: headingDeg)
        let transform = CATransform3DMakeRotation(CGFloat(radians), 0, 0, 1)
        if let lastHeading {
            let delta = abs(PersonCompass.shortestDelta(from: lastHeading, to: headingDeg))
            CATransaction.begin()
            CATransaction.setAnimationDuration(delta > 0.4 ? 0.16 : 0)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
            headingView.layer.transform = transform
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            headingView.layer.transform = transform
            CATransaction.commit()
        }
        lastHeading = headingDeg
    }
}

enum PersonCompassArt {
    static let rose: UIImage = renderRose()

    static func pin(tint: UIColor) -> UIImage {
        let size = CGFloat(PersonCompass.puckPoints)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let silver = UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 1)
            let cx = size / 2
            let r = size * 0.28
            let top = size * 0.06
            let tip = CGPoint(x: cx, y: size - 1.2)
            let head = CGPoint(x: cx, y: top + r)
            let path = UIBezierPath()
            path.addArc(
                withCenter: head,
                radius: r,
                startAngle: .pi * 0.78,
                endAngle: .pi * 2.22,
                clockwise: true
            )
            path.addLine(to: tip)
            path.close()
            cg.setFillColor(tint.cgColor)
            cg.addPath(path.cgPath)
            cg.fillPath()
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(1.1)
            cg.addPath(path.cgPath)
            cg.strokePath()
            let well = r * 0.58
            cg.setFillColor(UIColor(red: 0, green: 0, blue: 0, alpha: 0.78).cgColor)
            cg.fillEllipse(
                in: CGRect(x: cx - well, y: head.y - well, width: well * 2, height: well * 2)
            )
            cg.setStrokeColor(silver.cgColor)
            cg.setLineWidth(1)
            cg.strokeEllipse(
                in: CGRect(x: cx - well, y: head.y - well, width: well * 2, height: well * 2)
            )
        }
    }

    static func chevronPath(in bounds: CGRect) -> UIBezierPath {
        let cx = bounds.midX
        let top = bounds.minY + max(0.6, bounds.height * 0.02)
        let wing = max(2.4, bounds.width * 0.07)
        let height = max(3.6, bounds.height * 0.11)
        let notch = max(2.8, bounds.height * 0.085)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: cx, y: top))
        path.addLine(to: CGPoint(x: cx + wing, y: top + height))
        path.addLine(to: CGPoint(x: cx, y: top + notch))
        path.addLine(to: CGPoint(x: cx - wing, y: top + height))
        path.close()
        return path
    }

    private static func renderRose() -> UIImage {
        let size = CGFloat(PersonCompass.puckPoints)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let silver = UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 1)
            let accent = UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
            let center = CGPoint(x: size / 2, y: size / 2)
            let outer = size / 2 - 0.8
            let well = CGFloat(PersonCompass.wellPoints) / 2
            let band = max(2.2, outer - well - 1.4)

            cg.setFillColor(UIColor(red: 0, green: 0, blue: 0, alpha: 0.72).cgColor)
            cg.fillEllipse(in: CGRect(x: 0.6, y: 0.6, width: size - 1.2, height: size - 1.2))

            cg.setStrokeColor(silver.cgColor)
            cg.setLineWidth(1.4)
            cg.strokeEllipse(in: CGRect(x: 0.7, y: 0.7, width: size - 1.4, height: size - 1.4))

            cg.setStrokeColor(UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.28).cgColor)
            cg.setLineWidth(0.8)
            cg.strokeEllipse(
                in: CGRect(
                    x: center.x - well - 0.4,
                    y: center.y - well - 0.4,
                    width: (well + 0.4) * 2,
                    height: (well + 0.4) * 2
                )
            )

            for deg in stride(from: 0, to: 360, by: PersonCompass.minorTickEvery) {
                let major = deg % PersonCompass.majorTickEvery == 0
                let cardinal = deg % 90 == 0
                let length: CGFloat = cardinal ? band : (major ? band * 0.72 : band * 0.42)
                let width: CGFloat = cardinal ? 1.15 : (major ? 0.8 : 0.45)
                let alpha: CGFloat = cardinal ? 1 : (major ? 0.88 : 0.42)
                let color = deg == 0 ? accent : silver.withAlphaComponent(alpha)
                let rad = CGFloat(PersonCompass.tickRadians(headingDeg: Double(deg)))
                let outerR = outer - 0.6
                let innerR = outerR - length
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(width)
                cg.setLineCap(.square)
                cg.move(to: CGPoint(x: center.x + sin(rad) * innerR, y: center.y - cos(rad) * innerR))
                cg.addLine(to: CGPoint(x: center.x + sin(rad) * outerR, y: center.y - cos(rad) * outerR))
                cg.strokePath()
            }
        }
    }
}

extension PackStyle {
    public static func canvasColor(sun: Bool) -> UIColor {
        inkColor(sun ? sunFieldHex : voidInk)
    }

    public static func inkColor(_ hex: String) -> UIColor {
        var raw = hex
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// Real second palette. Not invert. Restore night paints first so
    /// widths and class fills never stack when SUN flips on and off.
    public static func applyHUDLamp(_ style: MLNStyle, sun: Bool) {
        capturePaintsIfNeeded(style)
        restorePaints(style)
        guard sun else { return }
        let field = inkColor(sunFieldHex)
        let ink = inkColor(sunInkHex)
        for layer in style.layers {
            paintSun(layer, field: field, ink: ink)
        }
    }

    private struct LampPaint {
        var backgroundColor: NSExpression?
        var fillColor: NSExpression?
        var fillOpacity: NSExpression?
        var lineColor: NSExpression?
        var lineOpacity: NSExpression?
        var lineWidth: NSExpression?
        var textColor: NSExpression?
        var textHaloColor: NSExpression?
        var textOpacity: NSExpression?
        var iconColor: NSExpression?
        var circleColor: NSExpression?
        var circleStrokeColor: NSExpression?
        var rasterOpacity: NSExpression?
        var rasterContrast: NSExpression?
        var rasterSaturation: NSExpression?
        var maximumRasterBrightness: NSExpression?
        var minimumRasterBrightness: NSExpression?
        var minZoom: Float = 0
    }

    private static var capturedStyle: ObjectIdentifier?
    private static var capturedPaints: [String: LampPaint] = [:]

    private static func capturePaintsIfNeeded(_ style: MLNStyle) {
        let id = ObjectIdentifier(style)
        if capturedStyle != id {
            capturedStyle = id
            capturedPaints = [:]
        }
        for layer in style.layers {
            if capturedPaints[layer.identifier] == nil {
                capturedPaints[layer.identifier] = snapshot(layer)
            }
        }
    }

    private static func restorePaints(_ style: MLNStyle) {
        for layer in style.layers {
            guard let paint = capturedPaints[layer.identifier] else { continue }
            restore(layer, paint)
        }
    }

    private static func snapshot(_ layer: MLNStyleLayer) -> LampPaint {
        var paint: LampPaint
        switch layer {
        case let background as MLNBackgroundStyleLayer:
            paint = LampPaint(backgroundColor: background.backgroundColor)
        case let fill as MLNFillStyleLayer:
            paint = LampPaint(fillColor: fill.fillColor, fillOpacity: fill.fillOpacity)
        case let line as MLNLineStyleLayer:
            paint = LampPaint(
                lineColor: line.lineColor,
                lineOpacity: line.lineOpacity,
                lineWidth: line.lineWidth
            )
        case let symbol as MLNSymbolStyleLayer:
            paint = LampPaint(
                textColor: symbol.textColor,
                textHaloColor: symbol.textHaloColor,
                textOpacity: symbol.textOpacity,
                iconColor: symbol.iconColor
            )
        case let circle as MLNCircleStyleLayer:
            paint = LampPaint(
                circleColor: circle.circleColor,
                circleStrokeColor: circle.circleStrokeColor
            )
        case let raster as MLNRasterStyleLayer:
            paint = LampPaint(
                rasterOpacity: raster.rasterOpacity,
                rasterContrast: raster.rasterContrast,
                rasterSaturation: raster.rasterSaturation,
                maximumRasterBrightness: raster.maximumRasterBrightness,
                minimumRasterBrightness: raster.minimumRasterBrightness
            )
        default:
            paint = LampPaint()
        }
        paint.minZoom = layer.minimumZoomLevel
        return paint
    }

    private static func restore(_ layer: MLNStyleLayer, _ paint: LampPaint) {
        switch layer {
        case let background as MLNBackgroundStyleLayer:
            if let color = paint.backgroundColor { background.backgroundColor = color }
        case let fill as MLNFillStyleLayer:
            if let color = paint.fillColor { fill.fillColor = color }
            if let opacity = paint.fillOpacity { fill.fillOpacity = opacity }
        case let line as MLNLineStyleLayer:
            if let color = paint.lineColor { line.lineColor = color }
            if let opacity = paint.lineOpacity { line.lineOpacity = opacity }
            if let width = paint.lineWidth { line.lineWidth = width }
        case let symbol as MLNSymbolStyleLayer:
            if let color = paint.textColor { symbol.textColor = color }
            if let halo = paint.textHaloColor { symbol.textHaloColor = halo }
            if let opacity = paint.textOpacity { symbol.textOpacity = opacity }
            if let icon = paint.iconColor { symbol.iconColor = icon }
        case let circle as MLNCircleStyleLayer:
            if let color = paint.circleColor { circle.circleColor = color }
            if let stroke = paint.circleStrokeColor { circle.circleStrokeColor = stroke }
        case let raster as MLNRasterStyleLayer:
            if let opacity = paint.rasterOpacity { raster.rasterOpacity = opacity }
            if let contrast = paint.rasterContrast { raster.rasterContrast = contrast }
            if let saturation = paint.rasterSaturation { raster.rasterSaturation = saturation }
            if let maxBright = paint.maximumRasterBrightness {
                raster.maximumRasterBrightness = maxBright
            }
            if let minBright = paint.minimumRasterBrightness {
                raster.minimumRasterBrightness = minBright
            }
        default:
            break
        }
        layer.minimumZoomLevel = paint.minZoom
    }

    private static func paintSun(_ layer: MLNStyleLayer, field: UIColor, ink: UIColor) {
        let id = layer.identifier
        if id.hasPrefix("khan-") { return }
        if id == aerialLayerID || id.hasPrefix("aerial") || id.hasPrefix("naip") { return }
        switch layer {
        case let background as MLNBackgroundStyleLayer:
            background.backgroundColor = NSExpression(forConstantValue: field)
        case let fill as MLNFillStyleLayer:
            guard id == landFillLayerID else { return }
            fill.fillColor = NSExpression(forConstantValue: field)
            fill.fillOpacity = NSExpression(forConstantValue: 1)
        case let line as MLNLineStyleLayer:
            guard !keepsLine(id) else { return }
            line.lineColor = NSExpression(forConstantValue: ink)
        case let symbol as MLNSymbolStyleLayer:
            symbol.textColor = NSExpression(forConstantValue: ink)
            symbol.textHaloColor = NSExpression(forConstantValue: field)
            symbol.iconColor = NSExpression(forConstantValue: ink)
        case let circle as MLNCircleStyleLayer:
            guard !keepsCircle(id) else { return }
            circle.circleColor = NSExpression(forConstantValue: ink)
            circle.circleStrokeColor = NSExpression(forConstantValue: field)
        case let raster as MLNRasterStyleLayer:
            raster.rasterOpacity = NSExpression(forConstantValue: 0.10)
        default:
            break
        }
    }

    private static func keepsLine(_ id: String) -> Bool {
        if id == "roads-arterial-casing" || id == "hazards" { return true }
        if id == RouteLine.coreLayerID { return true }
        if id.hasPrefix("water") { return true }
        if id.hasPrefix("public-land") { return true }
        if id.hasPrefix("flood") { return true }
        if id == "contours" { return true }
        return false
    }

    private static func keepsCircle(_ id: String) -> Bool {
        if id == DestinationPin.coreLayerID || id == DestinationPin.ringLayerID { return true }
        if id == HoldPin.coreLayerID || id == HoldPin.ringLayerID { return true }
        if id.contains("hit") { return true }
        if id.hasPrefix("you-puck") || id.hasPrefix("party") { return true }
        return false
    }

    public static func applyEyeLayers(
        _ style: MLNStyle,
        godsEye: Bool,
        layers: [EyeDesk.Layer]
    ) {
        let aerialWanted = !godsEye || EyeDesk.layerOn(.aerial, in: layers)
        let hasAerial = style.layers.contains {
            let id = $0.identifier
            return id == aerialLayerID || id.hasPrefix("aerial") || id.hasPrefix("naip")
        }
        let aerial = aerialWanted && hasAerial
        // USGS 3DEP hillshade is the pack floor. Walking keeps it under NAIP
        // so ground outside the photo is not void. EYE keeps it too: packed
        // NAIP starts at z14, so a pack-wide camera would otherwise be black.
        let shade = !godsEye || EyeDesk.layerOn(.shade, in: layers) || aerialWanted
        let water = !godsEye || EyeDesk.layerOn(.water, in: layers)
        for layer in style.layers {
            let id = layer.identifier
            if id == "hillshade" || id.hasPrefix("hillshade") {
                layer.isVisible = shade
                if godsEye, shade, let raster = layer as? MLNRasterStyleLayer {
                    paintKhanShade(raster)
                }
            }
            if id.hasPrefix("water-detail") {
                layer.isVisible = water
            }
            if id == aerialLayerID || id.hasPrefix("naip") || id.hasPrefix("aerial") {
                layer.isVisible = aerial
            }
            if coversPhoto(id) {
                layer.isVisible = !aerial
            }
            if godsEye, let fill = layer as? MLNFillStyleLayer, id == landFillLayerID {
                fill.fillOpacity = NSExpression(forConstantValue: aerial ? 0 : EyeDesk.khanLandOpacity)
            }
            if godsEye, id == "contours", let line = layer as? MLNLineStyleLayer {
                line.lineOpacity = NSExpression(forConstantValue: EyeDesk.khanContourOpacity)
                line.lineWidth = NSExpression(forConstantValue: EyeDesk.khanContourWidth)
            }
            if godsEye, holdsKhanDetail(id) {
                layer.minimumZoomLevel = Float(PackCamera.minZoom)
            }
            if id.hasPrefix("khan-") {
                layer.isVisible = true
            }
            if let symbol = layer as? MLNSymbolStyleLayer,
               id == roadLabelsLayerID || id == roadRefsLayerID || id == "water-labels"
                || id == "place-labels"
            {
                symbol.textOpacity = NSExpression(forConstantValue: 1)
            }
        }
    }

    /// Schematic fills and casings that sit on the photo. Hide them on walking
    /// MAP and KHAN EYE while packed NAIP is the ground so yards read. Labels stay.
    private static func coversPhoto(_ id: String) -> Bool {
        if id == landFillLayerID { return true }
        if id == "tracks" || id == "wild-roads" || id == "contours" { return true }
        if id == "public-land-fill" || id == "public-land-line" || id == "flood-fill" {
            return true
        }
        return id.hasPrefix("roads")
    }

    private static func holdsKhanDetail(_ id: String) -> Bool {
        id == roadLabelsLayerID
            || id == roadRefsLayerID
            || id == "water-labels"
            || id == "place-labels"
            || id == "tracks"
    }

    private static func paintKhanShade(_ raster: MLNRasterStyleLayer) {
        raster.rasterOpacity = NSExpression(forConstantValue: EyeDesk.khanShadeOpacity)
        raster.rasterContrast = NSExpression(forConstantValue: EyeDesk.khanShadeContrast)
        raster.rasterSaturation = NSExpression(forConstantValue: EyeDesk.khanShadeSaturation)
        raster.maximumRasterBrightness = NSExpression(
            forConstantValue: EyeDesk.khanShadeBrightnessMax
        )
        raster.minimumRasterBrightness = NSExpression(
            forConstantValue: EyeDesk.khanShadeBrightnessMin
        )
    }

    public static func applyEyePalette(
        _ style: MLNStyle,
        godsEye: Bool,
        palette: EyeDesk.Palette
    ) {
        guard godsEye else { return }
        switch palette {
        case .streets:
            return
        case .packIR:
            let heat = inkColor("#ED510A")
            let ice = inkColor("#2EE67A")
            for layer in style.layers {
                paintFalseColor(layer, heat: heat, ice: ice)
            }
        case .nvg:
            let green = UIColor(red: 0.18, green: 0.92, blue: 0.32, alpha: 1)
            let void = UIColor(red: 0, green: 0.08, blue: 0, alpha: 1)
            for layer in style.layers {
                paintNVG(layer, green: green, field: void)
            }
        }
    }

    private static func paintFalseColor(_ layer: MLNStyleLayer, heat: UIColor, ice: UIColor) {
        switch layer {
        case let fill as MLNFillStyleLayer:
            if layer.identifier == landFillLayerID {
                fill.fillColor = NSExpression(forConstantValue: heat)
            }
        case let raster as MLNRasterStyleLayer:
            raster.rasterOpacity = NSExpression(forConstantValue: 0.72)
        case let extrusion as MLNFillExtrusionStyleLayer:
            extrusion.fillExtrusionColor = NSExpression(forConstantValue: heat)
        case let circle as MLNCircleStyleLayer:
            if layer.identifier.hasPrefix("water") {
                circle.circleColor = NSExpression(forConstantValue: ice)
            }
        default:
            break
        }
    }

    private static func paintNVG(_ layer: MLNStyleLayer, green: UIColor, field: UIColor) {
        switch layer {
        case let background as MLNBackgroundStyleLayer:
            background.backgroundColor = NSExpression(forConstantValue: field)
        case let fill as MLNFillStyleLayer:
            fill.fillColor = NSExpression(forConstantValue: field)
        case let line as MLNLineStyleLayer:
            line.lineColor = NSExpression(forConstantValue: green)
        case let symbol as MLNSymbolStyleLayer:
            symbol.textColor = NSExpression(forConstantValue: green)
            symbol.textHaloColor = NSExpression(forConstantValue: field)
            symbol.iconColor = NSExpression(forConstantValue: green)
        case let circle as MLNCircleStyleLayer:
            circle.circleColor = NSExpression(forConstantValue: green)
        case let raster as MLNRasterStyleLayer:
            raster.rasterOpacity = NSExpression(forConstantValue: 0.55)
        case let extrusion as MLNFillExtrusionStyleLayer:
            extrusion.fillExtrusionColor = NSExpression(forConstantValue: green)
        default:
            break
        }
    }
}

enum EyeLook {
    static func tint(_ condition: String) -> UIColor {
        switch EyeDesk.condition(status: condition) {
        case .green:
            return UIColor(red: 46.0 / 255.0, green: 230.0 / 255.0, blue: 122.0 / 255.0, alpha: 1)
        case .yellow:
            return UIColor(red: 0.93, green: 0.75, blue: 0.22, alpha: 1)
        case .red:
            return UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
        }
    }
}