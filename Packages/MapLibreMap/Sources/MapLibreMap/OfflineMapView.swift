import Foundation

#if canImport(SwiftUI) && canImport(UIKit) && canImport(MapLibre)
import MapLibre
import SwiftUI
import UIKit

/// MapLibre Metal map. Local style only. No MapKit, no tile hosts.
public struct OfflineMapView: UIViewRepresentable {
    public var styleURL: URL
    public var centerLat: Double
    public var centerLon: Double

    public init(styleURL: URL, centerLat: Double, centerLon: Double) {
        self.styleURL = styleURL
        self.centerLat = centerLat
        self.centerLon = centerLon
    }

    public func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero, styleURL: styleURL)
        view.logoView.isHidden = false
        view.prefetchesTiles = false
        view.allowsRotating = true
        view.setCenter(CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon), zoomLevel: 13, animated: false)
        return view
    }

    public func updateUIView(_ uiView: MLNMapView, context: Context) {
        if uiView.styleURL != styleURL {
            uiView.styleURL = styleURL
        }
    }
}
#endif
