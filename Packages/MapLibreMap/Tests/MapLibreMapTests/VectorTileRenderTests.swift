#if canImport(UIKit)
import CoreLocation
import MapLibre
import UIKit
import XCTest

@testable import MapLibreMap

/// Renders the shipped pack in a simulator and asks the map what it drew.
///
/// Everything else in this repo can be checked by reading bytes. Whether
/// MapLibre resolves a local tile archive and puts El Paso on the glass cannot
/// be, and a map that ships blank is the one failure worth real machinery to
/// catch. These tests boot an actual `MLNMapView`, wait for it to go idle, and
/// query the features under the viewport.
@MainActor
final class VectorTileRenderTests: XCTestCase {
    /// The repo checkout, found from this file rather than a bundle, because the
    /// packs are source data and are not copied into the test bundle.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MapLibreMapTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // MapLibreMap
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
    }

    private static var packRoot: URL {
        repoRoot.appendingPathComponent("Resources/Packs/tx-west")
    }

    private static let downtownElPaso = CLLocationCoordinate2D(latitude: 31.7587, longitude: -106.4869)

    // MARK: - The question this file exists to answer

    /// MapLibre ships a PMTiles reader but documents no local-file URL spelling,
    /// and guessing wrong renders nothing. Try every plausible spelling against a
    /// real archive and let the renderer say which one it honours.
    func testTheRendererAgreesOnAPMTilesURLSpelling() throws {
        let archive = Self.packRoot.appendingPathComponent("osm.pmtiles")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: archive.path), "no pmtiles archive in the checkout")

        var worked: [String] = []
        for spelling in PMTilesURL.candidates(for: archive) {
            let style = try Self.styleJSON(vectorURL: spelling, glyphs: Self.packRoot)
            let drawn = try Self.render(style: style, at: Self.downtownElPaso, zoom: 15, layer: "roads")
            print("PMTILES-SPELLING \(spelling) -> \(drawn) features")
            if drawn > 0 { worked.append(spelling) }
        }
        XCTAssertFalse(
            worked.isEmpty,
            "no pmtiles:// spelling produced a single rendered street; the archive is unreadable to MapLibre"
        )
        // The shipped resolver must pick one the renderer actually honours.
        XCTAssertTrue(
            worked.contains(PMTilesURL.shipped(for: archive)),
            "the resolver ships \(PMTilesURL.shipped(for: archive)) but only \(worked) render"
        )
    }

    /// The pack is worth nothing if the streets under El Paso do not draw.
    func testDowntownElPasoDrawsNamedStreets() throws {
        let archive = Self.packRoot.appendingPathComponent("osm.pmtiles")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: archive.path), "no pmtiles archive in the checkout")
        let style = try Self.styleJSON(vectorURL: PMTilesURL.shipped(for: archive), glyphs: Self.packRoot)
        let names = try Self.renderedNames(style: style, at: Self.downtownElPaso, zoom: 15)
        XCTAssertGreaterThan(names.count, 20, "downtown El Paso came back with almost no street names: \(names)")
        for landmark in ["Mesa", "Piedras", "Alameda", "Montana", "Dyer"] {
            // Not every landmark falls in one viewport; assert the set is real.
            if names.contains(where: { $0.contains(landmark) }) { return }
        }
        XCTFail("none of the El Paso landmark streets drew; got \(names.prefix(20))")
    }

    // MARK: - Harness

    private static func styleJSON(vectorURL: String, glyphs: URL) throws -> URL {
        let style: [String: Any] = [
            "version": 8,
            "name": "render probe",
            "glyphs": PackStyle.localGlyphURL(template: "glyphs/{fontstack}/{range}.pbf", packRoot: glyphs),
            "sources": ["osm": ["type": "vector", "url": vectorURL]],
            "layers": [
                ["id": "void", "type": "background", "paint": ["background-color": "#000000"]],
                [
                    "id": "roads", "type": "line", "source": "osm", "source-layer": "road",
                    "paint": ["line-color": "#c8ccd4", "line-width": 3.0],
                ],
            ],
        ]
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("probe-\(abs(vectorURL.hashValue)).json")
        try JSONSerialization.data(withJSONObject: style).write(to: out)
        return out
    }

    /// Boot a map, wait for it to settle, and hand back what it put on screen.
    private static func withRenderedMap<T>(
        style: URL,
        at centre: CLLocationCoordinate2D,
        zoom: Double,
        read: (MLNMapView) -> T,
        fallback: T
    ) throws -> T {
        let frame = CGRect(x: 0, y: 0, width: 512, height: 512)
        let window = UIWindow(frame: frame)
        let view = MLNMapView(frame: frame, styleURL: style)
        let watcher = IdleWatcher()
        view.delegate = watcher
        window.addSubview(view)
        window.makeKeyAndVisible()
        view.setCenter(centre, zoomLevel: zoom, animated: false)

        // Pump the run loop rather than block it; the renderer needs it to turn.
        let deadline = Date().addingTimeInterval(60)
        while !watcher.idle, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        defer {
            view.removeFromSuperview()
            window.isHidden = true
        }
        guard watcher.idle else {
            XCTFail("map never finished drawing: \(watcher.failure ?? "timed out")")
            return fallback
        }
        return read(view)
    }

    private static func render(style: URL, at centre: CLLocationCoordinate2D, zoom: Double, layer: String) throws -> Int {
        try withRenderedMap(style: style, at: centre, zoom: zoom, read: { view in
            view.visibleFeatures(in: view.bounds, styleLayerIdentifiers: [layer]).count
        }, fallback: 0)
    }

    private static func renderedNames(style: URL, at centre: CLLocationCoordinate2D, zoom: Double) throws -> Set<String> {
        try withRenderedMap(style: style, at: centre, zoom: zoom, read: { view in
            var names = Set<String>()
            for feature in view.visibleFeatures(in: view.bounds, styleLayerIdentifiers: ["roads"]) {
                if let name = feature.attributes["name"] as? String { names.insert(name) }
            }
            return names
        }, fallback: [])
    }

    private final class IdleWatcher: NSObject, MLNMapViewDelegate {
        private(set) var idle = false
        private(set) var failure: String?

        func mapViewDidBecomeIdle(_ mapView: MLNMapView) { idle = true }
        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            failure = error.localizedDescription
            idle = true
        }
    }
}
#endif
