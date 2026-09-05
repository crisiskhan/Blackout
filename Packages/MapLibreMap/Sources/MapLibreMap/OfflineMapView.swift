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

    public init(
        styleURL: URL,
        centerLat: Double,
        centerLon: Double,
        puckLat: Double,
        puckLon: Double,
        packSouth: Double,
        packWest: Double,
        packNorth: Double,
        packEast: Double
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
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero, styleURL: styleURL)
        view.delegate = context.coordinator
        view.logoView.isHidden = false
        view.prefetchesTiles = false
        view.allowsRotating = true
        view.shouldRequestAuthorizationToUseLocationServices = true
        view.showsUserLocation = true
        view.backgroundColor = UIColor(red: 12.0 / 255.0, green: 14.0 / 255.0, blue: 16.0 / 255.0, alpha: 1)
        view.setCenter(
            CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            zoomLevel: 10,
            animated: false
        )
        context.coordinator.apply(overlaySpec, on: view, force: true)
        return view
    }

    public func updateUIView(_ uiView: MLNMapView, context: Context) {
        if uiView.styleURL != styleURL {
            uiView.styleURL = styleURL
        }
        uiView.shouldRequestAuthorizationToUseLocationServices = true
        uiView.showsUserLocation = true
        context.coordinator.apply(overlaySpec, on: uiView, force: false)
    }

    private var overlaySpec: Coordinator.OverlaySpec {
        Coordinator.OverlaySpec(
            puckLat: puckLat,
            puckLon: puckLon,
            packSouth: packSouth,
            packWest: packWest,
            packNorth: packNorth,
            packEast: packEast
        )
    }

    public final class Coordinator: NSObject, MLNMapViewDelegate {
        struct OverlaySpec {
            var puckLat: Double
            var puckLon: Double
            var packSouth: Double
            var packWest: Double
            var packNorth: Double
            var packEast: Double
        }

        var spec: OverlaySpec?
        var packOverlay: MLNPolygon?
        var packOutline: MLNPolyline?
        var puckHalo: MLNPolygon?
        var puck: MLNPointAnnotation?
        var storedPack: (south: Double, west: Double, north: Double, east: Double)?
        var storedPuck: (lat: Double, lon: Double)?
        var fittedPack: (south: Double, west: Double, north: Double, east: Double)?

        func apply(_ spec: OverlaySpec, on view: MLNMapView, force: Bool) {
            self.spec = spec
            applyCamera(spec, on: view, force: force)
            let mapHasPuck = (view.annotations ?? []).contains { ann in
                ann.title == UserPuck.title
                    && abs(ann.coordinate.latitude - spec.puckLat) < 1e-9
                    && abs(ann.coordinate.longitude - spec.puckLon) < 1e-9
            }
            let should = force || UserPuck.needsReapply(
                storedPack: storedPack,
                storedPuck: storedPuck,
                pack: (spec.packSouth, spec.packWest, spec.packNorth, spec.packEast),
                puck: (spec.puckLat, spec.puckLon),
                mapHasPuck: mapHasPuck
            )
            if !should {
                syncStyleOverlays(on: view, spec: spec)
                return
            }

            if let old = packOverlay {
                view.remove(old)
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
            let poly = MLNPolygon(coordinates: &ring, count: UInt(ring.count))
            view.add(poly)
            packOverlay = poly
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
            syncStyleOverlays(on: view, spec: spec)
        }

        func applyCamera(_ spec: OverlaySpec, on view: MLNMapView, force: Bool) {
            let pack = (spec.packSouth, spec.packWest, spec.packNorth, spec.packEast)
            if !force, let fitted = fittedPack, fitted == pack { return }
            guard view.bounds.width > 1, view.bounds.height > 1 else { return }
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
            fittedPack = pack
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
        }

        public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            mapView.shouldRequestAuthorizationToUseLocationServices = true
            mapView.showsUserLocation = true
            fittedPack = nil
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
            return UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 0.16)
        }

        public func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if annotation === puckHalo {
                return UIColor.white
            }
            return UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
        }

        public func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat {
            1
        }

        public func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            annotation === packOutline ? 3.5 : 2
        }
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
