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
        view.showsUserLocation = true
        view.setCenter(
            CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            zoomLevel: 13,
            animated: false
        )
        applyOverlays(view, coordinator: context.coordinator)
        return view
    }

    public func updateUIView(_ uiView: MLNMapView, context: Context) {
        if uiView.styleURL != styleURL {
            uiView.styleURL = styleURL
        }
        uiView.showsUserLocation = true
        applyOverlays(uiView, coordinator: context.coordinator)
    }

    private func applyOverlays(_ view: MLNMapView, coordinator: Coordinator) {
        let puckCoord = CLLocationCoordinate2D(latitude: puckLat, longitude: puckLon)
        let samePack = coordinator.packSouth == packSouth
            && coordinator.packWest == packWest
            && coordinator.packNorth == packNorth
            && coordinator.packEast == packEast
        let samePuck = coordinator.puck?.coordinate.latitude == puckLat
            && coordinator.puck?.coordinate.longitude == puckLon
        if samePack && samePuck { return }

        if let old = coordinator.packOverlay {
            view.removeOverlay(old)
        }
        if let old = coordinator.puck {
            view.removeAnnotation(old)
        }
        var ring = PackGeometry.bboxRing(
            south: packSouth,
            west: packWest,
            north: packNorth,
            east: packEast
        ).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let poly = MLNPolygon(coordinates: &ring, count: UInt(ring.count))
        view.addOverlay(poly)
        coordinator.packOverlay = poly
        coordinator.packSouth = packSouth
        coordinator.packWest = packWest
        coordinator.packNorth = packNorth
        coordinator.packEast = packEast

        let puck = MLNPointAnnotation()
        puck.coordinate = puckCoord
        puck.title = "YOU"
        view.addAnnotation(puck)
        coordinator.puck = puck
    }

    public final class Coordinator: NSObject, MLNMapViewDelegate {
        var packOverlay: MLNPolygon?
        var puck: MLNPointAnnotation?
        var packSouth: Double?
        var packWest: Double?
        var packNorth: Double?
        var packEast: Double?

        public func mapView(_ mapView: MLNMapView, fillColorForPolygonAnnotation annotation: MLNPolygon) -> UIColor {
            UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 0.16)
        }

        public func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
        }

        public func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat {
            1
        }
    }
}
