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
    public var packSouth: Double
    public var packWest: Double
    public var packNorth: Double
    public var packEast: Double
    public var route: [(lat: Double, lon: Double)]
    public var destination: (lat: Double, lon: Double)?
    /// The point the inspect card is about, marked so the card never hides it.
    public var held: (lat: Double, lon: Double)?
    /// Bumped by FIT PACK. Every other value change leaves the camera where the thumb left it.
    public var fitToken: Int
    /// UIKit `MLNMapView` ignores SwiftUI `allowsHitTesting`. This is the
    /// value that has to live on the Metal view.
    public var interactive: Bool
    public var onMapTap: ((Double, Double) -> Void)?
    /// A thumb held still on a place, with whatever the pack has drawn there,
    /// and the zoom so the water index can claim the same ground the thumb covers.
    public var onMapHold: ((Double, Double, [String: String], Double) -> Void)?
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
    /// WALK dashes the accent core. DRIVE keeps it solid. Chrome already
    /// says which; the line has to match.
    public var travelMode: TravelMode

    public init(
        styleURL: URL,
        centerLat: Double,
        centerLon: Double,
        puckLat: Double,
        puckLon: Double,
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
        pips: [PartyBody] = [],
        youHeading: Double? = nil,
        youEmblem: String = PersonEmblem.fallback.rawValue,
        onPulse: (() -> Void)? = nil,
        lockOn: Bool = false,
        travelMode: TravelMode = .walk
    ) {
        self.styleURL = styleURL
        self.centerLat = centerLat
        self.centerLon = centerLon
        self.puckLat = puckLat
        self.puckLon = puckLon
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
        self.pips = pips
        self.youHeading = youHeading
        self.youEmblem = youEmblem
        self.onPulse = onPulse
        self.lockOn = lockOn
        self.travelMode = travelMode
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
        view.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.setCenter(
            CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            zoomLevel: PackCamera.openZoom,
            animated: false
        )
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
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
        // Paper map. Two-finger rotate with the compass hidden loses north;
        // pitch turns a field sheet into a toy globe.
        view.allowsRotating = false
        view.allowsTilting = false
        if abs(view.direction) > 0.5 {
            view.setDirection(0, animated: false)
        }
    }

    private var overlaySpec: Coordinator.OverlaySpec {
        Coordinator.OverlaySpec(
            puckLat: puckLat,
            puckLon: puckLon,
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
            lockOn: lockOn,
            travelMode: travelMode
        )
    }

    public final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        struct OverlaySpec {
            var puckLat: Double
            var puckLon: Double
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
            var lockOn: Bool
            var travelMode: TravelMode
        }

        var spec: OverlaySpec?
        var onMapTap: ((Double, Double) -> Void)?
        var onMapHold: ((Double, Double, [String: String], Double) -> Void)?
        var onPulse: (() -> Void)?
        var trackUser = true
        var interactive = true
        private let holdTick = UIImpactFeedbackGenerator(style: .rigid)
        var packOutline: MLNPolyline?
        var routeLine: MLNPolyline?
        var puckHalo: MLNPolygon?
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
        var followedPuck: (lat: Double, lon: Double)?
        var storedMode: TravelMode?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard interactive, gesture.state == .ended, let view = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: view)
            let coord = view.convert(point, toCoordinateFrom: view)
            onMapTap?(coord.latitude, coord.longitude)
            onPulse?()
        }

        @objc func handleHold(_ gesture: UILongPressGestureRecognizer) {
            guard interactive, gesture.state == .began, let view = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: view)
            let coord = view.convert(point, toCoordinateFrom: view)
            holdTick.impactOccurred()
            onMapHold?(coord.latitude, coord.longitude, record(under: point, on: view), view.zoomLevel)
            onPulse?()
            liftIntoView(point, on: view)
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
        /// pack's ground geojson so a hold cannot read a pin.
        private func packWorkedGround(
            at coordinate: CLLocationCoordinate2D,
            style: MLNStyle
        ) -> [MLNFeature] {
            guard CLLocationCoordinate2DIsValid(coordinate) else { return [] }
            guard let source = style.source(withIdentifier: PackStyle.groundWorkedSourceID)
                    as? MLNShapeSource
            else { return [] }
            return source.features(matching: nil).filter { Self.covers($0, coordinate) }
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
            applyCamera(spec, on: view, force: force)
            let mapHasPuck = (view.annotations ?? []).contains { ann in
                ann.title == UserPuck.title
                    && abs(ann.coordinate.latitude - spec.puckLat) < 1e-9
                    && abs(ann.coordinate.longitude - spec.puckLon) < 1e-9
            }
            let puckNeeds = force || UserPuck.needsReapply(
                storedPack: storedPack,
                storedPuck: storedPuck,
                pack: (spec.packSouth, spec.packWest, spec.packNorth, spec.packEast),
                puck: (spec.puckLat, spec.puckLon),
                mapHasPuck: mapHasPuck
            )
            let routeNeeds = force || RouteLine.needsReapply(
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
                    if let old = puckHalo {
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

                    var halo = UserPuck.haloRing(lat: spec.puckLat, lon: spec.puckLon)
                        .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    let haloPoly = MLNPolygon(coordinates: &halo, count: UInt(halo.count))
                    view.add(haloPoly)
                    puckHalo = haloPoly

                    let you = PersonMarkAnnotation()
                    you.coordinate = CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon)
                    you.title = UserPuck.title
                    you.memberID = UserPuck.title
                    you.emblemID = spec.youEmblem
                    you.headingDeg = spec.youHeading
                    view.addAnnotation(you)
                    puck = you
                    storedPack = (spec.packSouth, spec.packWest, spec.packNorth, spec.packEast)
                    storedPuck = (spec.puckLat, spec.puckLon)
                    syncRoute(on: view, spec: spec, force: true)
                    syncStyleOverlays(on: view, spec: spec)
                    storedDestination = spec.destination
                    storedHeld = spec.held
                    storedPips = spec.pips
                    storedMode = spec.travelMode
                }
            }
            syncPersonMarks(on: view, spec: spec)
        }

        func syncPersonMarks(on view: MLNMapView, spec: OverlaySpec) {
            if let you = puck as? PersonMarkAnnotation {
                you.coordinate = CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon)
                you.emblemID = spec.youEmblem
                you.headingDeg = spec.youHeading
                if let mark = view.view(for: you) as? YouPuckAnnotationView {
                    mark.apply(emblemID: spec.youEmblem, headingDeg: spec.youHeading)
                }
            }
            syncPartyMarks(on: view, spec: spec)
        }

        func syncPartyMarks(on view: MLNMapView, spec: OverlaySpec) {
            let existing = Dictionary(uniqueKeysWithValues: partyMarks.map { ($0.memberID, $0) })
            var next: [PersonMarkAnnotation] = []
            var seen = Set<String>()
            for pip in spec.pips {
                seen.insert(pip.id)
                if let old = existing[pip.id] {
                    old.coordinate = CLLocationCoordinate2D(latitude: pip.lat, longitude: pip.lon)
                    old.emblemID = pip.emblem
                    old.headingDeg = pip.headingDeg
                    if let mark = view.view(for: old) as? YouPuckAnnotationView {
                        mark.apply(emblemID: pip.emblem, headingDeg: pip.headingDeg)
                    }
                    next.append(old)
                } else {
                    let mark = PersonMarkAnnotation()
                    mark.coordinate = CLLocationCoordinate2D(latitude: pip.lat, longitude: pip.lon)
                    mark.title = "\(PartyPips.titlePrefix)\(pip.id)"
                    mark.memberID = pip.id
                    mark.emblemID = pip.emblem
                    mark.headingDeg = pip.headingDeg
                    view.addAnnotation(mark)
                    next.append(mark)
                }
            }
            for old in partyMarks where !seen.contains(old.memberID) {
                view.removeAnnotation(old)
            }
            partyMarks = next
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
            let pack = (spec.packSouth, spec.packWest, spec.packNorth, spec.packEast)
            let size = (width: Double(view.bounds.width), height: Double(view.bounds.height))
            if spec.fitToken != fittedFitToken {
                fittedFitToken = spec.fitToken
                fitPack(spec, on: view)
                fittedPack = pack
                fittedSize = size
                storedLockOn = spec.lockOn
                if spec.lockOn {
                    followedPuck = (spec.puckLat, spec.puckLon)
                } else {
                    followedPuck = nil
                }
                return
            }
            if PackCamera.shouldFitRoute(
                lockOn: spec.lockOn,
                stored: storedRoute,
                route: spec.route
            ) {
                fitRoute(spec, on: view)
                fittedPack = pack
                fittedSize = size
                storedLockOn = spec.lockOn
                followedPuck = spec.lockOn ? (spec.puckLat, spec.puckLon) : nil
                return
            }
            if PackCamera.shouldFollow(
                lockOn: spec.lockOn,
                wasLocked: storedLockOn,
                lastFollow: followedPuck,
                puck: (spec.puckLat, spec.puckLon)
            ) {
                view.setCenter(
                    CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon),
                    animated: storedLockOn
                )
                followedPuck = (spec.puckLat, spec.puckLon)
            }
            storedLockOn = spec.lockOn
            if !spec.lockOn {
                followedPuck = nil
            }
            if spec.lockOn {
                if force || PackCamera.shouldRefit(
                    fittedPack: fittedPack,
                    pack: pack,
                    fittedSize: fittedSize,
                    size: size
                ) {
                    view.setCenter(
                        CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon),
                        animated: false
                    )
                    fittedPack = pack
                    fittedSize = size
                }
                return
            }
            if !force, !PackCamera.shouldRefit(
                fittedPack: fittedPack,
                pack: pack,
                fittedSize: fittedSize,
                size: size
            ) { return }
            view.setCenter(
                CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon),
                zoomLevel: PackCamera.openZoom,
                animated: false
            )
            fittedPack = pack
            fittedSize = size
        }

        func fitPack(_ spec: OverlaySpec, on view: MLNMapView) {
            let box = PackCamera.bounds(
                south: spec.packSouth,
                west: spec.packWest,
                north: spec.packNorth,
                east: spec.packEast
            )
            let bounds = MLNCoordinateBoundsMake(
                CLLocationCoordinate2D(latitude: box.south, longitude: box.west),
                CLLocationCoordinate2D(latitude: box.north, longitude: box.east)
            )
            let pad = CGFloat(PackCamera.edgePaddingPoints)
            view.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: pad, left: 16, bottom: pad, right: 16),
                animated: false,
                completionHandler: nil
            )
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
                    forConstantValue: UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 1)
                )
                layer.lineWidth = NSExpression(forConstantValue: 3)
                style.addLayer(layer)
            }

            let you = MLNPointFeature()
            you.coordinate = CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon)
            if let src = style.source(withIdentifier: "you-puck-src") as? MLNShapeSource {
                src.shape = you
            } else {
                let src = MLNShapeSource(identifier: "you-puck-src", shape: you, options: nil)
                style.addSource(src)
                let halo = MLNCircleStyleLayer(identifier: "you-puck-halo", source: src)
                halo.circleColor = NSExpression(
                    forConstantValue: UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.32)
                )
                halo.circleRadius = NSExpression(forConstantValue: 22)
                halo.circleStrokeColor = NSExpression(
                    forConstantValue: UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
                )
                halo.circleStrokeWidth = NSExpression(forConstantValue: 3)
                halo.circleOpacity = NSExpression(forConstantValue: 0)
                style.addLayer(halo)
                let core = MLNCircleStyleLayer(identifier: "you-puck-core", source: src)
                core.circleColor = NSExpression(forConstantValue: UIColor.white)
                core.circleRadius = NSExpression(forConstantValue: 8)
                core.circleOpacity = NSExpression(forConstantValue: 0)
                style.addLayer(core)
            }

            if let dest = spec.destination {
                let pin = MLNPointFeature()
                pin.coordinate = CLLocationCoordinate2D(latitude: dest.lat, longitude: dest.lon)
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
                var empty = [CLLocationCoordinate2D]()
                src.shape = MLNPolyline(coordinates: &empty, count: 0)
            }

            if let point = spec.held {
                let mark = MLNPointFeature()
                mark.coordinate = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
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
                var empty = [CLLocationCoordinate2D]()
                src.shape = MLNPolyline(coordinates: &empty, count: 0)
            }

            if RouteLine.shouldDraw(spec.route) {
                var coords = spec.route.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                }
                let line = MLNPolyline(coordinates: &coords, count: UInt(coords.count))
                if let src = style.source(withIdentifier: RouteLine.sourceID) as? MLNShapeSource {
                    src.shape = line
                    paintRoute(on: style, source: src, mode: spec.travelMode)
                } else {
                    let src = MLNShapeSource(identifier: RouteLine.sourceID, shape: line, options: nil)
                    style.addSource(src)
                    paintRoute(on: style, source: src, mode: spec.travelMode)
                }
            } else if let src = style.source(withIdentifier: RouteLine.sourceID) as? MLNShapeSource {
                var empty = [CLLocationCoordinate2D]()
                src.shape = MLNPolyline(coordinates: &empty, count: 0)
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
                halo.circleOpacity = NSExpression(forConstantValue: 0)
                style.addLayer(halo)
                let core = MLNCircleStyleLayer(identifier: PartyPips.coreLayerID, source: src)
                core.circleColor = NSExpression(
                    forConstantValue: UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 1)
                )
                core.circleRadius = NSExpression(forConstantValue: PartyPips.coreRadius)
                core.circleStrokeColor = NSExpression(forConstantValue: UIColor.black)
                core.circleStrokeWidth = NSExpression(forConstantValue: 2)
                core.circleOpacity = NSExpression(forConstantValue: 0)
                style.addLayer(core)
            }
        }

        /// Void casing, silver fill, scarce accent core. Streets at walking zoom
        /// are silver with a void or red casing; a single silver stroke of the
        /// same width disappears into them. WALK dashes only the core so the
        /// path never reads as another arterial; DRIVE stays a solid thread.
        func paintRoute(on style: MLNStyle, source: MLNSource, mode: TravelMode) {
            let silver = UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 1)
            let accent = UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
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
            stroke(casing, color: UIColor.black, width: RouteLine.casingWidth, dashed: false)

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
            let features: [[String: Any]] = pips.map { pip in
                [
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
            guard
                let data = try? JSONSerialization.data(withJSONObject: geo),
                let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
            else {
                var empty = [CLLocationCoordinate2D]()
                return MLNPolyline(coordinates: &empty, count: 0)
            }
            return shape
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

        public func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if annotation is MLNUserLocation {
                return nil
            }
            let you = annotation.title == UserPuck.title
            let reuse = you ? "you-puck" : "party-puck"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? YouPuckAnnotationView)
                ?? YouPuckAnnotationView(reuseIdentifier: reuse)
            if let mark = annotation as? PersonMarkAnnotation {
                view.apply(emblemID: mark.emblemID, headingDeg: mark.headingDeg)
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
            if annotation === puckHalo {
                return UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.38)
            }
            return .clear
        }

        public func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if annotation === puckHalo {
                return UIColor.white
            }
            if annotation === routeLine {
                return UIColor.clear
            }
            return UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 1)
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

    override func layoutSubviews() {
        super.layoutSubviews()
        onBoundsChange?(bounds.size)
    }
}

final class PersonMarkAnnotation: MLNPointAnnotation {
    var memberID = ""
    var emblemID: String?
    var headingDeg: Double?
}

final class YouPuckAnnotationView: MLNAnnotationView {
    private let rose = UIImageView()
    private let emblemView = UIImageView()
    private let headingView = UIView()
    private let chevronLayer = CAShapeLayer()
    private var lastHeading: Double?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        let size = CGFloat(PersonCompass.puckPoints)
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        backgroundColor = .clear
        isOpaque = false
        isEnabled = false
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
    }

    func apply(emblemID: String?, headingDeg: Double?) {
        let emblem = PersonEmblem.resolved(emblemID)
        emblemView.image = PersonEmblem.image(emblem) ?? PersonEmblem.image(.fallback)
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

    static func chevronPath(in bounds: CGRect) -> UIBezierPath {
        let cx = bounds.midX
        let top = bounds.minY + 1.6
        let path = UIBezierPath()
        path.move(to: CGPoint(x: cx, y: top))
        path.addLine(to: CGPoint(x: cx + 5.4, y: top + 9.2))
        path.addLine(to: CGPoint(x: cx, y: top + 7.1))
        path.addLine(to: CGPoint(x: cx - 5.4, y: top + 9.2))
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
            let outer = size / 2 - 1.1
            let well = CGFloat(PersonCompass.wellPoints) / 2

            cg.setFillColor(UIColor(red: 0, green: 0, blue: 0, alpha: 0.72).cgColor)
            cg.fillEllipse(in: CGRect(x: 1, y: 1, width: size - 2, height: size - 2))

            cg.setStrokeColor(silver.cgColor)
            cg.setLineWidth(2.3)
            cg.strokeEllipse(in: CGRect(x: 1.15, y: 1.15, width: size - 2.3, height: size - 2.3))

            cg.setStrokeColor(UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.22).cgColor)
            cg.setLineWidth(1)
            cg.strokeEllipse(
                in: CGRect(
                    x: center.x - well - 0.6,
                    y: center.y - well - 0.6,
                    width: (well + 0.6) * 2,
                    height: (well + 0.6) * 2
                )
            )

            for deg in stride(from: 0, to: 360, by: PersonCompass.minorTickEvery) {
                let major = deg % PersonCompass.majorTickEvery == 0
                let cardinal = deg % 90 == 0
                let length: CGFloat = cardinal ? 6.6 : (major ? 5.0 : 3.0)
                let width: CGFloat = cardinal ? 1.45 : (major ? 1.0 : 0.55)
                let alpha: CGFloat = cardinal ? 1 : (major ? 0.88 : 0.42)
                let color = deg == 0 ? accent : silver.withAlphaComponent(alpha)
                let rad = CGFloat(PersonCompass.tickRadians(headingDeg: Double(deg)))
                let outerR = outer - 1.2
                let innerR = outerR - length
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(width)
                cg.setLineCap(.square)
                cg.move(to: CGPoint(x: center.x + sin(rad) * innerR, y: center.y - cos(rad) * innerR))
                cg.addLine(to: CGPoint(x: center.x + sin(rad) * outerR, y: center.y - cos(rad) * outerR))
                cg.strokePath()
            }

            let font = UIFont.systemFont(ofSize: 8, weight: .heavy)
            let labels: [(String, Int, UIColor)] = [
                ("N", 0, accent),
                ("E", 90, silver),
                ("S", 180, silver),
                ("W", 270, silver),
            ]
            for (text, deg, color) in labels {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                ]
                let draw = NSString(string: text)
                let textSize = draw.size(withAttributes: attrs)
                let rad = CGFloat(PersonCompass.tickRadians(headingDeg: Double(deg)))
                let r = well + 8.4
                let p = CGPoint(
                    x: center.x + sin(rad) * r - textSize.width / 2,
                    y: center.y - cos(rad) * r - textSize.height / 2
                )
                draw.draw(at: p, withAttributes: attrs)
            }
        }
    }
}
