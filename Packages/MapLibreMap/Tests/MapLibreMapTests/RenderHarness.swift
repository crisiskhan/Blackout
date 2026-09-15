#if canImport(UIKit)
import CoreLocation
import MapLibre
import UIKit
import XCTest

@testable import MapLibreMap

/// Boots a real `MLNMapView` over a shipped pack and hands back what it drew.
///
/// Shared by the tile tests and the hold tests. Both need MapLibre to resolve
/// the local archive, draw the layers and answer a query against them before
/// their question means anything, and there is no way to ask that without a
/// renderer: a map that ships blank looks perfect from the outside.
///
/// Reuse the renderer per style URL. Booting a fresh `MLNMapView` on every
/// hold aborted MapLibreMapTests at ~160/175 on the simulator: the process
/// died after packing more Holds into one XCTest run, and xcodebuild
/// returned 65 after `Executed 160 tests, with 0 failures`.
@MainActor
enum RenderHarness {
    /// The repo checkout, found from this file rather than a bundle, because
    /// the packs are source data and are not copied into the test bundle.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MapLibreMapTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // MapLibreMap
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
    }

    static func packRoot(_ pack: String) -> URL {
        repoRoot.appendingPathComponent("Resources/Packs/\(pack)")
    }

    static var txWest: URL { packRoot("tx-west") }
    static var txEast: URL { packRoot("tx-east") }
    static var nm: URL { packRoot("nm") }

    private struct Booted {
        let window: UIWindow
        let view: MLNMapView
        let watcher: IdleWatcher
    }

    /// One live map per resolved style. Three shipped packs, not one map
    /// per Hold. Do not tear the window down after a read.
    private static var boots: [URL: Booted] = [:]

    /// Skip rather than fail when the archive is not in the checkout, so the
    /// suite still runs somewhere the packs have not been fetched.
    static func requireArchive(in pack: URL) throws -> URL {
        let archive = pack.appendingPathComponent("osm.pmtiles")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: archive.path),
            "no pmtiles archive in the checkout"
        )
        return archive
    }

    /// The style the app ships, resolved the way the app resolves it — same
    /// glyph rewrite, same archive URL spelling, same generated vector layers.
    /// A hold reads whatever layers the style put up, so a hand-rolled probe
    /// style would be testing a map nobody runs.
    static func shippedStyle(pack: URL) throws -> URL {
        let cache = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("render-harness", isDirectory: true)
        return try PackStyle.resolved(
            styleAt: pack.appendingPathComponent("style.json"),
            packRoot: pack,
            cacheDirectory: cache
        )
    }

    /// Boot a map, wait for it to settle, and hand back what it put on screen.
    static func withRenderedMap<T>(
        style: URL,
        at centre: CLLocationCoordinate2D,
        zoom: Double,
        read: (MLNMapView) -> T,
        fallback: T
    ) throws -> T {
        let booted: Booted
        let firstBoot: Bool
        if let existing = boots[style] {
            booted = existing
            firstBoot = false
            existing.watcher.reset()
            existing.view.setCenter(centre, zoomLevel: zoom, animated: false)
        } else {
            let frame = CGRect(x: 0, y: 0, width: 512, height: 512)
            let window = UIWindow(frame: frame)
            let view = MLNMapView(frame: frame, styleURL: style)
            let watcher = IdleWatcher()
            view.delegate = watcher
            window.addSubview(view)
            window.makeKeyAndVisible()
            view.setCenter(centre, zoomLevel: zoom, animated: false)
            booted = Booted(window: window, view: view, watcher: watcher)
            boots[style] = booted
            firstBoot = true
        }
        // First boot has to see idle or the style never loaded. Reuse only
        // moved the camera; if idle does not fire again, do not sit for 60s
        // per Hold (that is how 38 places in one test become a leftover).
        waitUntilIdle(booted.watcher, timeout: firstBoot ? 60 : 8)
        if firstBoot, !booted.watcher.idle {
            XCTFail("map never finished drawing: \(booted.watcher.failure ?? "timed out")")
            return fallback
        }
        return read(booted.view)
    }

    private static func waitUntilIdle(_ watcher: IdleWatcher, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !watcher.idle, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private final class IdleWatcher: NSObject, MLNMapViewDelegate {
        private(set) var idle = false
        private(set) var failure: String?

        func reset() {
            idle = false
            failure = nil
        }

        func mapViewDidBecomeIdle(_ mapView: MLNMapView) { idle = true }
        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            failure = error.localizedDescription
            idle = true
        }
    }
}
#endif
