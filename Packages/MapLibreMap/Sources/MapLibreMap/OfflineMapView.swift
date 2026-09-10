import CoreLocation
import Foundation
import MapLibre
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
    public var onMapTap: ((Double, Double) -> Void)?
    /// A thumb held still on a place, with whatever the pack has drawn there.
    public var onMapHold: ((Double, Double, [String: String]) -> Void)?

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
        onMapTap: ((Double, Double) -> Void)? = nil,
        onMapHold: ((Double, Double, [String: String]) -> Void)? = nil
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
        self.onMapTap = onMapTap
        self.onMapHold = onMapHold
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
        view.logoView.isHidden = false
        view.prefetchesTiles = false
        view.allowsRotating = true
        view.shouldRequestAuthorizationToUseLocationServices = true
        view.showsUserLocation = true
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
        context.coordinator.apply(overlaySpec, on: view, force: true)
        return view
    }

    public func updateUIView(_ uiView: MLNMapView, context: Context) {
        if uiView.styleURL != styleURL {
            uiView.styleURL = styleURL
        }
        uiView.shouldRequestAuthorizationToUseLocationServices = true
        uiView.showsUserLocation = true
        context.coordinator.onMapTap = onMapTap
        context.coordinator.onMapHold = onMapHold
        context.coordinator.apply(overlaySpec, on: uiView, force: false)
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
            fitToken: fitToken
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
        }

        var spec: OverlaySpec?
        var onMapTap: ((Double, Double) -> Void)?
        var onMapHold: ((Double, Double, [String: String]) -> Void)?
        private let holdTick = UIImpactFeedbackGenerator(style: .rigid)
        var packOutline: MLNPolyline?
        var routeLine: MLNPolyline?
        var puckHalo: MLNPolygon?
        var puck: MLNPointAnnotation?
        var storedPack: (south: Double, west: Double, north: Double, east: Double)?
        var storedPuck: (lat: Double, lon: Double)?
        var storedRoute: [(lat: Double, lon: Double)]?
        var storedDestination: (lat: Double, lon: Double)?
        var storedHeld: (lat: Double, lon: Double)?
        var fittedPack: (south: Double, west: Double, north: Double, east: Double)?
        var fittedSize: (width: Double, height: Double)?
        var fittedFitToken = 0

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: view)
            let coord = view.convert(point, toCoordinateFrom: view)
            onMapTap?(coord.latitude, coord.longitude)
        }

        @objc func handleHold(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let view = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: view)
            let coord = view.convert(point, toCoordinateFrom: view)
            holdTick.impactOccurred()
            onMapHold?(coord.latitude, coord.longitude, record(under: point, on: view))
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
        /// falls inside it is added to the ranking. The puck, the route and
        /// the pin are still skipped: they are the app talking to itself.
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
            return Inspect.pick((painted + points).map(Self.tags(from:)))
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
            let routeNeeds = force || RouteLine.needsReapply(stored: storedRoute, route: spec.route)
            let destNeeds = force || DestinationPin.needsReapply(
                stored: storedDestination,
                destination: spec.destination
            )
            // Both pins live in the same style pass, so either one moving is
            // reason enough to run it.
            let heldNeeds = force || HoldPin.needsReapply(stored: storedHeld, held: spec.held)
            if !OverlaySync.needsStyleMutation(
                force: force,
                puckNeedsReapply: puckNeeds,
                routeNeedsReapply: routeNeeds,
                destinationNeedsReapply: destNeeds || heldNeeds
            ) {
                return
            }
            if !puckNeeds {
                syncRoute(on: view, spec: spec, force: force)
                syncStyleOverlays(on: view, spec: spec)
                storedDestination = spec.destination
                storedHeld = spec.held
                return
            }

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

            let you = MLNPointAnnotation()
            you.coordinate = CLLocationCoordinate2D(latitude: spec.puckLat, longitude: spec.puckLon)
            you.title = UserPuck.title
            view.addAnnotation(you)
            puck = you
            storedPack = (spec.packSouth, spec.packWest, spec.packNorth, spec.packEast)
            storedPuck = (spec.puckLat, spec.puckLon)
            syncRoute(on: view, spec: spec, force: true)
            syncStyleOverlays(on: view, spec: spec)
            storedDestination = spec.destination
            storedHeld = spec.held
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
                    forConstantValue: UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
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
                halo.circleColor = NSExpression(forConstantValue: UIColor(white: 1, alpha: 0.32))
                halo.circleRadius = NSExpression(forConstantValue: 22)
                halo.circleStrokeColor = NSExpression(
                    forConstantValue: UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
                )
                halo.circleStrokeWidth = NSExpression(forConstantValue: 3)
                style.addLayer(halo)
                let core = MLNCircleStyleLayer(identifier: "you-puck-core", source: src)
                core.circleColor = NSExpression(forConstantValue: UIColor.white)
                core.circleRadius = NSExpression(forConstantValue: 8)
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
                    ring.circleColor = NSExpression(forConstantValue: UIColor(white: 1, alpha: 0.18))
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
                } else {
                    let src = MLNShapeSource(identifier: RouteLine.sourceID, shape: line, options: nil)
                    style.addSource(src)
                    let layer = MLNLineStyleLayer(identifier: RouteLine.layerID, source: src)
                    layer.lineColor = NSExpression(
                        forConstantValue: UIColor(red: 0.12, green: 0.82, blue: 0.94, alpha: 1)
                    )
                    layer.lineWidth = NSExpression(forConstantValue: 6.5)
                    style.addLayer(layer)
                }
            } else if let src = style.source(withIdentifier: RouteLine.sourceID) as? MLNShapeSource {
                var empty = [CLLocationCoordinate2D]()
                src.shape = MLNPolyline(coordinates: &empty, count: 0)
            }
        }

        public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            mapView.shouldRequestAuthorizationToUseLocationServices = true
            mapView.showsUserLocation = true
            fittedPack = nil
            fittedSize = nil
            if let spec {
                apply(spec, on: mapView, force: true)
            }
        }

        public func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if annotation is MLNUserLocation {
                return nil
            }
            let reuse = "you-puck"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuse) ?? YouPuckAnnotationView(reuseIdentifier: reuse)
            return view
        }

        public func mapView(styleForDefaultUserLocationAnnotationView mapView: MLNMapView) -> MLNUserLocationAnnotationViewStyle {
            let style = MLNUserLocationAnnotationViewStyle()
            style.puckFillColor = .white
            style.puckShadowColor = .black
            style.puckShadowOpacity = 0.85
            style.puckArrowFillColor = UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
            style.haloFillColor = UIColor(white: 1, alpha: 0.35)
            return style
        }

        public func mapView(_ mapView: MLNMapView, fillColorForPolygonAnnotation annotation: MLNPolygon) -> UIColor {
            if annotation === puckHalo {
                return UIColor(white: 1, alpha: 0.38)
            }
            return .clear
        }

        public func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if annotation === puckHalo {
                return UIColor.white
            }
            if annotation === routeLine {
                return UIColor(red: 0.12, green: 0.82, blue: 0.94, alpha: 1)
            }
            return UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
        }

        public func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat {
            1
        }

        public func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            if annotation === routeLine { return 6.5 }
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

final class YouPuckAnnotationView: MLNAnnotationView {
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        bounds = CGRect(x: 0, y: 0, width: 44, height: 52)
        backgroundColor = .clear
        isOpaque = false
        scalesWithViewingDistance = false

        let halo = UIView(frame: CGRect(x: 4, y: 0, width: 36, height: 36))
        halo.backgroundColor = UIColor(white: 1, alpha: 0.28)
        halo.layer.cornerRadius = 18
        addSubview(halo)

        let core = UIView(frame: CGRect(x: 12, y: 8, width: 20, height: 20))
        core.backgroundColor = .white
        core.layer.cornerRadius = 10
        core.layer.borderWidth = 3
        core.layer.borderColor = UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1).cgColor
        addSubview(core)

        let label = UILabel(frame: CGRect(x: 0, y: 36, width: 44, height: 16))
        label.text = UserPuck.title
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 9, weight: .heavy)
        label.textColor = .white
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
