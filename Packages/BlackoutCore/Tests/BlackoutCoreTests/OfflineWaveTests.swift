import BlackoutCore
import XCTest

final class OfflineWaveTests: XCTestCase {
    func testGuideSendIsIdOnly() {
        let id = "party-split"
        let data = GuideCardWire.encode(articleID: id)
        XCTAssertEqual(GuideCardWire.decode(data), id)
        XCTAssertTrue(GuideCardWire.isIdOnly(data, expectedID: id))
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("Stay the rest of the group") == true)
        XCTAssertEqual(GuideCardWire.envelopeKind, .guideCard)
        XCTAssertNotEqual(GuideCardWire.envelopeKind, .message)
        XCTAssertEqual(GuideCardWire.missingCopy, "Card not on this pack")
    }

    func testDeadReckonPointsMarkedEstimated() {
        let gps = LocationFix(latitude: 31.76, longitude: -106.48, source: .gps)
        let dead = LocationFix(latitude: 31.77, longitude: -106.49, source: .deadReckoning)
        XCTAssertFalse(DeadReckoningHonesty.crumbEstimated(fix: gps))
        XCTAssertTrue(DeadReckoningHonesty.crumbEstimated(fix: dead))
        XCTAssertTrue(DeadReckoningHonesty.isEstimated(source: .deadReckoning))
        XCTAssertFalse(DeadReckoningHonesty.drawnAsGPS(source: .deadReckoning))
        XCTAssertTrue(DeadReckoningHonesty.drawnAsGPS(source: .gps))
        let crumb = BreadcrumbRecordDTO(
            expeditionID: BlackoutID(),
            latitude: 31.77,
            longitude: -106.49,
            estimated: true
        )
        XCTAssertTrue(crumb.estimated)
        XCTAssertFalse(DeadReckoningHonesty.chipVisible(gpsLive: true, isDeadReckoning: false))
        XCTAssertTrue(DeadReckoningHonesty.chipVisible(gpsLive: false, isDeadReckoning: true))
        XCTAssertFalse(DeadReckoningHonesty.canDeadReckon(motionDenied: true))
        XCTAssertEqual(DeadReckoningHonesty.chip, "Dead reckoning, GPS lost.")
    }

    func testSearchPatternStaysInPackBBox() {
        let region = MapRegion(
            name: "El Paso clip",
            centerLatitude: 31.7619,
            centerLongitude: -106.485,
            spanLatitude: 0.8,
            spanLongitude: 0.8,
            minZoom: 10,
            maxZoom: 12
        )
        for kind in SearchPatternKind.allCases {
            let line = SearchPattern.polyline(
                kind: kind,
                originLatitude: 31.7619,
                originLongitude: -106.485,
                region: region,
                stepMeters: 400
            )
            XCTAssertFalse(line.isEmpty, "\(kind) empty")
            XCTAssertTrue(SearchPattern.staysInPackBBox(points: line, region: region), "\(kind) left bbox")
        }
        let outside = SearchPattern.clamp(latitude: 40, longitude: -80, region: region)
        XCTAssertTrue(region.contains(latitude: outside.0, longitude: outside.1))
        XCTAssertFalse(SearchPattern.autoSOS)
    }

    func testRelayStopsAtTwoPercentAndLeave() {
        XCTAssertTrue(
            LeaveBehindRelayPolicy.isActive(enabled: true, expeditionOpen: true, batteryCritical: false)
        )
        XCTAssertFalse(
            LeaveBehindRelayPolicy.isActive(enabled: true, expeditionOpen: true, batteryCritical: true)
        )
        XCTAssertFalse(
            LeaveBehindRelayPolicy.isActive(enabled: true, expeditionOpen: false, batteryCritical: false)
        )
        XCTAssertTrue(LeaveBehindRelayPolicy.shouldStop(leaveOrEnd: true, batteryCritical: false))
        XCTAssertTrue(LeaveBehindRelayPolicy.shouldStop(leaveOrEnd: false, batteryCritical: true))
        XCTAssertFalse(LeaveBehindRelayPolicy.shouldStop(leaveOrEnd: false, batteryCritical: false))
        XCTAssertEqual(LeaveBehindRelayPolicy.banner, "Relay on. Mesh stays up.")
    }

    func testNightModeIsNotLightMode() {
        XCTAssertFalse(NightRedMode.isLightMode)
        XCTAssertTrue(NightRedMode.preferredSchemeDark)
        XCTAssertFalse(NightRedMode.raisesBrightness)
        let chrome = NightRedMode.chromeColor(on: true)
        XCTAssertEqual(chrome.red, 1, accuracy: 0.001)
        XCTAssertEqual(chrome.green, 43 / 255, accuracy: 0.001)
        let off = NightRedMode.typeColor(on: false)
        XCTAssertGreaterThan(off.green, 0.8)
        let on = NightRedMode.typeColor(on: true)
        XCTAssertEqual(on.red, 1, accuracy: 0.001)
        XCTAssertLessThan(on.green, 0.35)
    }

    func testFieldJobModeUsesExistingArticleIds() {
        XCTAssertEqual(FieldJobMode.partySplit.articleID, "party-split")
        XCTAssertEqual(FieldJobMode.kidLost.articleID, "kid-lost")
        XCTAssertEqual(FieldJobMode.kidHeat.articleID, "kid-heat")
        XCTAssertEqual(FieldJobMode.kidBite.articleID, "kid-bite")
        XCTAssertFalse(FieldJobMode.replacesSOS)
        XCTAssertEqual(FieldJobMode.from(articleID: "party-split"), .partySplit)
        XCTAssertNil(FieldJobMode.from(articleID: "edible-berry"))
    }

    func testFollowTrackDisabledWithoutCrumbs() {
        XCTAssertFalse(FollowTrackWire.canShare(crumbs: []))
        XCTAssertEqual(FollowTrackWire.emptyReason, "No track yet.")
        XCTAssertEqual(FollowTrackWire.disabledOpacity, 0.38, accuracy: 0.001)
        let one = BreadcrumbRecordDTO(expeditionID: BlackoutID(), latitude: 31.7, longitude: -106.4)
        XCTAssertFalse(FollowTrackWire.canShare(crumbs: [one]))
        let two = BreadcrumbRecordDTO(expeditionID: BlackoutID(), latitude: 31.71, longitude: -106.41)
        XCTAssertTrue(FollowTrackWire.canShare(crumbs: [one, two]))
    }

    func testViewshedUsesDroppedPinWhenLocationDenied() {
        let pin = LocationFix(latitude: 31.8, longitude: -106.5, source: .manualPin)
        let here = LocationFix(latitude: 39.74, longitude: -105.25, source: .lastKnown)
        let origin = ViewshedPolicy.origin(locationDenied: true, navigationFix: here, droppedPin: pin)
        XCTAssertEqual(origin?.latitude, 31.8)
        XCTAssertEqual(origin?.source, .manualPin)
        XCTAssertNil(ViewshedPolicy.origin(locationDenied: true, navigationFix: here, droppedPin: nil))
        XCTAssertFalse(ViewshedPolicy.toggleEnabled(hasDEM: false))
        XCTAssertEqual(ViewshedPolicy.noDEM, "No DEM.")
    }

    func testPackRelayNameAllowlist() {
        XCTAssertTrue(PackRelayPolicy.isRelayable("el-paso"))
        XCTAssertTrue(PackRelayPolicy.isRelayable("us-tx"))
        XCTAssertFalse(PackRelayPolicy.isRelayable("../secret"))
        XCTAssertFalse(PackRelayPolicy.sendEnabled(nearbyPeerCount: 0))
        XCTAssertTrue(PackRelayPolicy.sendEnabled(nearbyPeerCount: 1))
        XCTAssertEqual(PackRelayPolicy.sendLabel, "Send pack")
    }
}
