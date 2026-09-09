#if canImport(UIKit)
import CoreLocation
import MapLibre
import UIKit
import XCTest

@testable import MapLibreMap

/// A hold on the shipped Texas West archive, run on a real renderer.
///
/// `InspectTests` proves the reading is right for a given bag of tags, and the
/// Python guards prove those tags are in the pack. Neither proves the thing the
/// phone does: that putting a finger on a tank in El Paso and holding still
/// puts a card on the glass. Between the tags on disk and the card there is a
/// tile archive, a style, a 44pt query and a layer skip-list, and every one of
/// them can silently answer nothing.
///
/// So these boot the style the app boots, point the camera at coordinates taken
/// straight out of the extract, and call the app's own probe — the same
/// `record(under:on:)` the long-press handler calls. The coordinates are in the
/// test because they are evidence: each one is a real record in
/// `Resources/Packs/tx-west/osm.geojson`.
@MainActor
final class HoldOnTheGlassTests: XCTestCase {
    /// A `content=water` storage tank west of the pass. The record says what is
    /// in it, so the card is allowed to say water.
    private static let waterTank = CLLocationCoordinate2D(latitude: 31.78359, longitude: -106.70104)

    /// A storage tank carrying no `content` at all, which is what most tanks
    /// out here are. There is a service road 35 tile units off, so this one
    /// also checks that water outranks the street beside it.
    private static let silentTank = CLLocationCoordinate2D(latitude: 31.92497, longitude: -106.76375)

    /// Unnamed desert on the north-west edge of the pack, with nothing else
    /// mapped within twice the probe box. This is the empty-ground hold.
    private static let emptyDesert = CLLocationCoordinate2D(latitude: 31.94284, longitude: -106.75415)

    /// `Sierra de Ciudad Juárez` — ground the record does put a name to.
    private static let namedGround = CLLocationCoordinate2D(latitude: 31.71809, longitude: -106.61330)

    // MARK: - The two holds the build is gated on

    func testHoldingAWaterTankSaysWater() throws {
        let card = try hold(at: Self.waterTank, zoom: 16)
        XCTAssertEqual(card?.klass, "Water tank", "a content=water tank did not read as water: \(describe(card))")
        XCTAssertEqual(card?.kind, .water)
        XCTAssertEqual(card?.advice, .treat, "water still has to be treated")
        XCTAssertGreaterThanOrEqual(card?.sure ?? 0, 70, "the record says what is in it, so be sure of it")
    }

    func testHoldingEmptyDesertSaysGround() throws {
        let card = try hold(at: Self.emptyDesert, zoom: 15)
        XCTAssertNotNil(card, "holding empty desert put nothing on the glass")
        XCTAssertEqual(card?.kind, .land, "empty desert did not read as ground: \(describe(card))")
        XCTAssertEqual(card?.title, "Unnamed", "the record has no name for it and the card must not invent one")
        XCTAssertFalse(card?.klass.isEmpty ?? true, "ground came back with no class at all")
        XCTAssertEqual(card?.advice, .field, "empty ground sends you to Field")
    }

    // MARK: - The ones that keep it honest

    /// The failure that would matter most: a bare tank reading as water because
    /// `man_made=storage_tank` sounds like it holds some. Around El Paso only
    /// 110 of 585 storage tanks carry `content=water`.
    func testHoldingATankWithNoContentDoesNotPromiseWater() throws {
        let card = try hold(at: Self.silentTank, zoom: 16)
        XCTAssertNotNil(card, "holding a mapped tank put nothing on the glass")
        XCTAssertNotEqual(card?.klass, "Water tank", "a tank with no content tag was read as water: \(describe(card))")
        XCTAssertEqual(card?.advice, .leave, "an unknown tank is a leave-it")
        XCTAssertLessThan(card?.sure ?? 100, 60, "nobody wrote down what is in it, so do not sound sure")
    }

    func testHoldingNamedGroundUsesTheNameTheRecordGaveIt() throws {
        let card = try hold(at: Self.namedGround, zoom: 15)
        XCTAssertNotNil(card, "holding the Sierra de Ciudad Juárez put nothing on the glass")
        XCTAssertEqual(card?.kind, .land)
        XCTAssertTrue(
            card?.title.contains("Sierra de Ciudad Juárez") ?? false,
            "the ground is named in the record and the card dropped it: \(describe(card))"
        )
    }

    /// Whatever came back, it has to carry the four lines the card shows and a
    /// Field card to open. A reading with an empty `why` renders as `SURE 68% —`
    /// and looks broken.
    func testEveryHoldOnTheGlassFillsInTheWholeCard() throws {
        for (place, coordinate, zoom) in [
            ("water tank", Self.waterTank, 16.0),
            ("silent tank", Self.silentTank, 16.0),
            ("empty desert", Self.emptyDesert, 15.0),
            ("named ground", Self.namedGround, 15.0),
        ] {
            guard let card = try hold(at: coordinate, zoom: zoom) else {
                XCTFail("\(place) put nothing on the glass")
                continue
            }
            XCTAssertFalse(card.title.isEmpty, "\(place) has no title")
            XCTAssertFalse(card.klass.isEmpty, "\(place) has no class")
            XCTAssertFalse(card.why.isEmpty, "\(place) has no reason, so SURE reads as a bare number")
            XCTAssertFalse(card.fieldCardID.isEmpty, "\(place) opens no Field card")
            XCTAssertEqual(card.packDate, try Self.packDate(), "\(place) lost the pack date")
            XCTAssertTrue((1...100).contains(card.sure), "\(place) SURE out of range: \(card.sure)")
        }
    }

    // MARK: - Harness

    /// When the pack's OSM was pulled, as the manifest recorded it — the same
    /// string `AppRuntime` hands the card.
    private static func packDate() throws -> String {
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: RenderHarness.txWest.appendingPathComponent("manifest.json"))
        ) as? [String: Any]
        return try XCTUnwrap(manifest?["osmFetched"] as? String, "the pack does not say when it was pulled")
    }

    /// Hold in the middle of the viewport, through the app's own probe.
    private func hold(at centre: CLLocationCoordinate2D, zoom: Double) throws -> Inspect.Card? {
        let pack = RenderHarness.txWest
        _ = try RenderHarness.requireArchive(in: pack)
        let style = try RenderHarness.shippedStyle(pack: pack)
        let tags = try RenderHarness.withRenderedMap(
            style: style,
            at: centre,
            zoom: zoom,
            read: { view in
                OfflineMapView.Coordinator().record(
                    under: CGPoint(x: view.bounds.midX, y: view.bounds.midY),
                    on: view
                )
            },
            fallback: [:]
        )
        guard !tags.isEmpty else { return nil }
        return Inspect.read(tags: tags, packDate: try Self.packDate())
    }

    private func describe(_ card: Inspect.Card?) -> String {
        guard let card else { return "nothing" }
        return "\(card.title) / \(card.klass) / \(card.kind) / \(card.sureLine)"
    }
}
#endif
