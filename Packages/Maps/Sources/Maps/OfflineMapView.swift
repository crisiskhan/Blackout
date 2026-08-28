import BlackoutCore
import MapKit
import SwiftUI
import UIKit

struct OfflineMapView: UIViewRepresentable {
    var pack: MapPackSnapshot?
    var selfFix: LocationFix?
    var breadcrumbs: [BreadcrumbRecordDTO]
    var pois: [MapPOI]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.backgroundColor = UIColor(red: 7 / 255, green: 8 / 255, blue: 10 / 255, alpha: 1)
        map.pointOfInterestFilter = .excludingAll
        map.showsTraffic = false
        map.showsCompass = false
        map.showsScale = false
        map.isPitchEnabled = false
        map.showsUserLocation = false
        map.tintColor = UIColor(red: 244 / 255, green: 247 / 255, blue: 250 / 255, alpha: 1)
        context.coordinator.installOverlay(on: map, pack: pack)
        if let pack {
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: pack.region.centerLatitude, longitude: pack.region.centerLongitude),
                span: MKCoordinateSpan(latitudeDelta: pack.region.spanLatitude, longitudeDelta: pack.region.spanLongitude)
            )
            map.setRegion(region, animated: false)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        if context.coordinator.packRoot != pack?.rootURL {
            context.coordinator.installOverlay(on: map, pack: pack)
        }
        context.coordinator.syncAnnotations(
            on: map,
            selfFix: selfFix,
            breadcrumbs: breadcrumbs,
            pois: pois
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var packRoot: URL?
        private var overlay: BundledTileOverlay?

        func installOverlay(on map: MKMapView, pack: MapPackSnapshot?) {
            if let overlay {
                map.removeOverlay(overlay)
            }
            packRoot = pack?.rootURL
            guard let pack else { return }
            let next = BundledTileOverlay(
                packRoot: pack.rootURL,
                minZoom: pack.region.minZoom,
                maxZoom: pack.region.maxZoom
            )
            overlay = next
            map.addOverlay(next, level: .aboveLabels)
        }

        func syncAnnotations(
            on map: MKMapView,
            selfFix: LocationFix?,
            breadcrumbs: [BreadcrumbRecordDTO],
            pois: [MapPOI]
        ) {
            map.removeAnnotations(map.annotations)
            if let selfFix, selfFix.hasCoordinate,
               let lat = selfFix.latitude, let lon = selfFix.longitude {
                let pin = MKPointAnnotation()
                pin.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                pin.title = "You"
                pin.subtitle = "Last known / live"
                map.addAnnotation(pin)
            }
            for crumb in breadcrumbs where crumb.hasCoordinate {
                let pin = MKPointAnnotation()
                pin.coordinate = CLLocationCoordinate2D(latitude: crumb.latitude!, longitude: crumb.longitude!)
                pin.title = "Breadcrumb"
                map.addAnnotation(pin)
            }
            for poi in pois {
                let pin = MKPointAnnotation()
                pin.coordinate = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
                pin.title = poi.name
                pin.subtitle = poi.kind
                map.addAnnotation(pin)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tile)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let id = "blackout.pin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = true
            if annotation.title == "You" {
                view.markerTintColor = UIColor(red: 110 / 255, green: 200 / 255, blue: 1, alpha: 1)
                view.glyphImage = UIImage(systemName: "location.north.fill")
            } else if annotation.title == "Breadcrumb" {
                view.markerTintColor = UIColor(red: 197 / 255, green: 205 / 255, blue: 214 / 255, alpha: 1)
                view.glyphImage = UIImage(systemName: "point.3.connected.trianglepath.dotted")
            } else {
                view.markerTintColor = UIColor(red: 92 / 255, green: 101 / 255, blue: 112 / 255, alpha: 1)
            }
            return view
        }
    }
}
