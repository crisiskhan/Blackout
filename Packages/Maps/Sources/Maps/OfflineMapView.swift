import BlackoutCore
import Darwin
import DesignSystem
import MapsChrome
import MapsRouting
import SwiftUI
import UIKit

private func darwinCos(_ radians: Double) -> CGFloat { CGFloat(Darwin.cos(radians)) }
private func darwinSin(_ radians: Double) -> CGFloat { CGFloat(Darwin.sin(radians)) }
private func darwinHypot(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    CGFloat(Darwin.hypot(Double(x), Double(y)))
}
private func darwinAtan2(_ y: CGFloat, _ x: CGFloat) -> Double {
    Darwin.atan2(Double(y), Double(x))
}

/// File-tile map. Does **not** create MKMapView, so Apple raster/CDN is not on first paint.
struct OfflineMapView: UIViewRepresentable {
    var pack: MapPackSnapshot
    var selfFix: LocationFix?
    var manualPin: LocationFix?
    var breadcrumbs: [BreadcrumbRecordDTO]
    var viewshed: [ViewshedRay]
    var slope: [SlopeSample]
    var showViewshed: Bool
    var viewshedOrigin: LocationFix? = nil
    var showSlope: Bool
    var centerToken: Int
    /// When true, Recenter pinned the camera to the covering pack. GPS follow
    /// must not yank the camera off those tiles or into a void.
    var pinCameraToPack: Bool
    var routing: RoutingPack?
    var routeLine: [RoutingCoordinate]
    var destination: RoutingCoordinate?
    var showPackTiles: Bool
    var showStreets: Bool = false
    var showTopoTiles: Bool = false
    var showTrails: Bool
    var jumpToken: Int = 0
    var jumpCoordinate: RoutingCoordinate? = nil
    var headingDegrees: Double?
    var accuracyMeters: Double?
    var packContainsSelf: Bool
    var activeManeuver: Maneuver?
    var inboundPing: LocationFix? = nil
    var inboundPingHue: FieldPingHue? = nil
    var searchPattern: [(Double, Double)] = []
    var sharedTrack: [FollowTrackWire.Point] = []
    var amenityPins: [RoutingPOI] = []
    var markPins: [RoutingCoordinate] = []
    var onDropPin: (Double, Double) -> Void
    var onTap: ((Double, Double) -> Void)?
    var onUserInteract: (() -> Void)?
    var onScaleChange: ((Double) -> Void)?
    var onOutsidePack: (Bool) -> Void
    var resetToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDropPin: onDropPin,
            onTap: onTap,
            onUserInteract: onUserInteract,
            onScaleChange: onScaleChange,
            onOutsidePack: onOutsidePack
        )
    }

    func makeUIView(context: Context) -> OfflineTileScrollView {
        let view = OfflineTileScrollView(pack: pack)
        if MapChromeLock.canvasUIViewAutoresizes {
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        view.coordinator = context.coordinator
        view.applyOverlays(
            selfFix: selfFix,
            manualPin: manualPin,
            breadcrumbs: breadcrumbs,
            viewshed: viewshed,
            slope: slope,
            showViewshed: showViewshed,
            viewshedOrigin: viewshedOrigin,
            showSlope: showSlope,
            routing: routing,
            routeLine: routeLine,
            destination: destination,
            showPackTiles: showPackTiles,
            showStreets: showStreets,
            showTopoTiles: showTopoTiles,
            showTrails: showTrails,
            headingDegrees: headingDegrees,
            accuracyMeters: accuracyMeters,
            packContainsSelf: packContainsSelf,
            activeManeuver: activeManeuver,
            inboundPing: inboundPing,
            inboundPingHue: inboundPingHue,
            searchPattern: searchPattern,
            sharedTrack: sharedTrack,
            amenityPins: amenityPins,
            markPins: markPins
        )
        return view
    }

    func updateUIView(_ view: OfflineTileScrollView, context: Context) {
        context.coordinator.onDropPin = onDropPin
        context.coordinator.onTap = onTap
        context.coordinator.onUserInteract = onUserInteract
        context.coordinator.onScaleChange = onScaleChange
        context.coordinator.onOutsidePack = onOutsidePack
        view.coordinator = context.coordinator
        view.applyOverlays(
            selfFix: selfFix,
            manualPin: manualPin,
            breadcrumbs: breadcrumbs,
            viewshed: viewshed,
            slope: slope,
            showViewshed: showViewshed,
            viewshedOrigin: viewshedOrigin,
            showSlope: showSlope,
            routing: routing,
            routeLine: routeLine,
            destination: destination,
            showPackTiles: showPackTiles,
            showStreets: showStreets,
            showTopoTiles: showTopoTiles,
            showTrails: showTrails,
            headingDegrees: headingDegrees,
            accuracyMeters: accuracyMeters,
            packContainsSelf: packContainsSelf,
            activeManeuver: activeManeuver,
            inboundPing: inboundPing,
            inboundPingHue: inboundPingHue,
            searchPattern: searchPattern,
            sharedTrack: sharedTrack,
            amenityPins: amenityPins,
            markPins: markPins
        )
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            view.recenterToPackCoverage()
        }
        if context.coordinator.lastCenterToken != centerToken {
            context.coordinator.lastCenterToken = centerToken
            // Heading-up / follow-puck only while GPS is on this pack.
            // Recenter pins coverage. GPS outside the pack never yanks the camera.
            if MapEmptyPolicy.followGPS(pinToPack: pinCameraToPack, packContainsSelf: packContainsSelf),
               let selfFix, selfFix.hasCoordinate {
                view.centerOn(latitude: selfFix.latitude!, longitude: selfFix.longitude!)
            }
        }
        if context.coordinator.lastJumpToken != jumpToken {
            context.coordinator.lastJumpToken = jumpToken
            if let jump = jumpCoordinate {
                view.centerOn(latitude: jump.latitude, longitude: jump.longitude)
            }
        }
    }

    final class Coordinator {
        var onDropPin: (Double, Double) -> Void
        var onTap: ((Double, Double) -> Void)?
        var onUserInteract: (() -> Void)?
        var onScaleChange: ((Double) -> Void)?
        var onOutsidePack: (Bool) -> Void
        var lastResetToken = 0
        var lastCenterToken = 0
        var lastJumpToken = 0

        init(
            onDropPin: @escaping (Double, Double) -> Void,
            onTap: ((Double, Double) -> Void)?,
            onUserInteract: (() -> Void)?,
            onScaleChange: ((Double) -> Void)?,
            onOutsidePack: @escaping (Bool) -> Void
        ) {
            self.onDropPin = onDropPin
            self.onTap = onTap
            self.onUserInteract = onUserInteract
            self.onScaleChange = onScaleChange
            self.onOutsidePack = onOutsidePack
        }
    }
}

final class OfflineTileScrollView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var coordinator: OfflineMapView.Coordinator?
    private let pack: MapPackSnapshot
    private let overlay: BundledTileOverlay
    private let scroll = UIScrollView()
    private let canvas = TileCanvasLayer()
    private let x0: Int
    private let y0: Int
    private let zMax: Int
    private let zMin: Int
    private var lastOutside = false
    private var didFit = false
    private var didPaint = false
    private var lastDrawnZoom: Int?

    init(pack: MapPackSnapshot) {
        self.pack = pack
        zMax = pack.region.maxZoom
        zMin = pack.region.minZoom
        overlay = BundledTileOverlay(
            packRoot: pack.rootURL,
            minZoom: pack.region.minZoom,
            maxZoom: pack.region.maxZoom
        )
        let west = pack.region.centerLongitude - pack.region.spanLongitude / 2
        let east = pack.region.centerLongitude + pack.region.spanLongitude / 2
        let south = pack.region.centerLatitude - pack.region.spanLatitude / 2
        let north = pack.region.centerLatitude + pack.region.spanLatitude / 2
        x0 = Int(floor(WebMercator.tileX(longitude: west, zoom: zMax)))
        let x1 = Int(floor(WebMercator.tileX(longitude: east, zoom: zMax)))
        y0 = Int(floor(WebMercator.tileY(latitude: north, zoom: zMax)))
        let y1 = Int(floor(WebMercator.tileY(latitude: south, zoom: zMax)))
        super.init(frame: .zero)
        if MapChromeLock.canvasUIViewAutoresizes {
            autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        backgroundColor = UIColor(red: 7 / 255, green: 8 / 255, blue: 10 / 255, alpha: 1)
        scroll.delegate = self
        scroll.backgroundColor = backgroundColor
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bounces = true
        scroll.bouncesZoom = true
        if MapChromeLock.canvasUIViewAutoresizes {
            scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        addSubview(scroll)
        canvas.overlay = overlay
        canvas.x0 = x0
        canvas.y0 = y0
        canvas.zMax = zMax
        canvas.zMin = zMin
        canvas.cols = max(1, x1 - x0 + 1)
        canvas.rows = max(1, y1 - y0 + 1)
        canvas.backgroundColor = backgroundColor
        canvas.frame = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(canvas.cols) * 256,
            height: CGFloat(canvas.rows) * 256
        )
        scroll.addSubview(canvas)
        scroll.contentSize = canvas.frame.size
        scroll.minimumZoomScale = 0.2
        scroll.maximumZoomScale = 4
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.55
        canvas.addGestureRecognizer(press)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        canvas.addGestureRecognizer(tap)
        canvas.isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        if !didFit, bounds.width > 0, canvas.bounds.width > 0 {
            didFit = true
            recenterToPackCoverage()
        }
        reportOutside()
        reportScale()
    }

    func recenterToPackCoverage() {
        let cover = MapChromeLock.coverZoomScale(
            viewWidth: Double(bounds.width),
            viewHeight: Double(bounds.height),
            canvasWidth: Double(canvas.bounds.width),
            canvasHeight: Double(canvas.bounds.height)
        )
        let scale = CGFloat(cover)
        scroll.minimumZoomScale = max(scale, 0.01)
        scroll.maximumZoomScale = max(4, scale * 4)
        scroll.setZoomScale(scale, animated: false)
        lastDrawnZoom = canvas.currentZoom()
        centerPack()
        // Manifest center (Denver / Front Range). Never GPS / last-known.
        centerOn(latitude: pack.region.centerLatitude, longitude: pack.region.centerLongitude)
        lastOutside = false
        coordinator?.onOutsidePack(false)
        reportOutside()
    }

    func applyOverlays(
        selfFix: LocationFix?,
        manualPin: LocationFix?,
        breadcrumbs: [BreadcrumbRecordDTO],
        viewshed: [ViewshedRay],
        slope: [SlopeSample],
        showViewshed: Bool,
        viewshedOrigin: LocationFix?,
        showSlope: Bool,
        routing: RoutingPack?,
        routeLine: [RoutingCoordinate],
        destination: RoutingCoordinate?,
        showPackTiles: Bool,
        showStreets: Bool,
        showTopoTiles: Bool,
        showTrails: Bool,
        headingDegrees: Double?,
        accuracyMeters: Double?,
        packContainsSelf: Bool,
        activeManeuver: Maneuver?,
        inboundPing: LocationFix?,
        inboundPingHue: FieldPingHue?,
        searchPattern: [(Double, Double)],
        sharedTrack: [FollowTrackWire.Point],
        amenityPins: [RoutingPOI],
        markPins: [RoutingCoordinate]
    ) {
        let headingDirty = MapChromeLock.shouldRedrawForHeading(
            previous: canvas.headingDegrees,
            next: headingDegrees
        )
        let fixDirty = MapChromeLock.shouldRedrawForFix(
            previousLat: canvas.selfFix?.latitude,
            previousLon: canvas.selfFix?.longitude,
            nextLat: selfFix?.latitude,
            nextLon: selfFix?.longitude
        )
        let layersDirty = canvas.showPackTiles != showPackTiles
            || canvas.showStreets != showStreets
            || canvas.showTopoTiles != showTopoTiles
            || canvas.showTrails != showTrails
        let routeDirty = canvas.routeLine.count != routeLine.count
            || canvas.destination?.latitude != destination?.latitude
            || canvas.destination?.longitude != destination?.longitude
        let pinsDirty = canvas.amenityPins.count != amenityPins.count
            || canvas.markPins.count != markPins.count
            || canvas.packContainsSelf != packContainsSelf
        canvas.selfFix = selfFix
        canvas.manualPin = manualPin
        canvas.breadcrumbs = breadcrumbs
        canvas.viewshed = viewshed
        canvas.slope = slope
        canvas.showViewshed = showViewshed
        canvas.viewshedOrigin = viewshedOrigin
        canvas.showSlope = showSlope
        canvas.routing = routing
        canvas.routeLine = routeLine
        canvas.destination = destination
        canvas.showPackTiles = showPackTiles
        canvas.showStreets = showStreets
        canvas.showTopoTiles = showTopoTiles
        canvas.showTrails = showTrails
        canvas.headingDegrees = headingDegrees
        canvas.accuracyMeters = accuracyMeters
        canvas.packContainsSelf = packContainsSelf
        canvas.activeManeuver = activeManeuver
        canvas.inboundPing = inboundPing
        canvas.inboundPingHue = inboundPingHue
        canvas.searchPattern = searchPattern
        canvas.sharedTrack = sharedTrack
        canvas.amenityPins = amenityPins
        canvas.markPins = markPins
        if !didPaint || headingDirty || fixDirty || layersDirty || routeDirty || pinsDirty {
            didPaint = true
            invalidateVisibleCanvas()
        }
    }

    func centerOn(latitude: Double, longitude: Double) {
        let fix = LocationFix(latitude: latitude, longitude: longitude)
        guard let point = canvas.point(for: fix) else { return }
        let scaled = CGPoint(x: point.x * scroll.zoomScale, y: point.y * scroll.zoomScale)
        let x = scaled.x - scroll.bounds.width / 2 + scroll.contentInset.left
        let y = scaled.y - scroll.bounds.height / 2 + scroll.contentInset.top
        scroll.setContentOffset(CGPoint(x: max(-scroll.contentInset.left, x), y: max(-scroll.contentInset.top, y)), animated: false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        coordinator?.onUserInteract?()
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        coordinator?.onUserInteract?()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        canvas.zoomScale = scrollView.zoomScale
        redrawCanvasIfZoomIntegerChanged()
        clampCamera()
        reportOutside()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        canvas.zoomScale = scrollView.zoomScale
        redrawCanvasIfZoomIntegerChanged()
        clampCamera()
        reportOutside()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        reportScale()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        reportScale()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { reportScale() }
    }

    private func redrawCanvasIfZoomIntegerChanged() {
        let zoom = canvas.currentZoom()
        let changed = lastDrawnZoom != zoom
        lastDrawnZoom = zoom
        if MapChromeLock.shouldRedrawAfterScroll(zoomIntegerChanged: changed) {
            invalidateVisibleCanvas()
            reportScale()
        }
    }

    private func visibleCanvasRect() -> CGRect {
        let scale = max(scroll.zoomScale, CGFloat(0.01))
        let pad = CGFloat(256)
        let raw = CGRect(
            x: scroll.contentOffset.x / scale - pad,
            y: scroll.contentOffset.y / scale - pad,
            width: scroll.bounds.width / scale + pad * 2,
            height: scroll.bounds.height / scale + pad * 2
        )
        if scroll.bounds.isEmpty || canvas.bounds.isEmpty {
            return canvas.bounds
        }
        let hit = raw.intersection(canvas.bounds.insetBy(dx: -pad, dy: -pad))
        return hit.isNull || hit.isEmpty ? canvas.bounds : hit
    }

    private func invalidateVisibleCanvas() {
        if MapChromeLock.canvasRedrawsVisibleRectOnly {
            canvas.setNeedsDisplay(visibleCanvasRect())
        } else {
            canvas.setNeedsDisplay()
        }
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        coordinator?.onUserInteract?()
        let point = gesture.location(in: canvas)
        let lonlat = canvas.coordinate(at: point)
        coordinator?.onDropPin(lonlat.0, lonlat.1)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        coordinator?.onUserInteract?()
        let point = gesture.location(in: canvas)
        let lonlat = canvas.coordinate(at: point)
        coordinator?.onTap?(lonlat.0, lonlat.1)
    }

    private func reportScale() {
        guard MapChromeLock.paintsScaleBarOnMap
            || MapChromeLock.paintsWalkScaleAndCompass
            || MapChromeLock.reportsScaleOnEveryScroll else { return }
        let zoom = Double(zMax) + Darwin.log2(Double(max(scroll.zoomScale, 0.01)))
        let meters = MapScaleBarMath.metersPerPoint(
            latitude: pack.region.centerLatitude,
            zoom: zoom
        )
        coordinator?.onScaleChange?(meters)
    }

    private func centerPack() {
        let extraX = max(0, (scroll.bounds.width - canvas.frame.width) / 2)
        let extraY = max(0, (scroll.bounds.height - canvas.frame.height) / 2)
        scroll.contentInset = UIEdgeInsets(top: extraY, left: extraX, bottom: extraY, right: extraX)
        let x = max(0, (scroll.contentSize.width - scroll.bounds.width) / 2)
        let y = max(0, (scroll.contentSize.height - scroll.bounds.height) / 2)
        scroll.contentOffset = CGPoint(x: x - scroll.contentInset.left, y: y - scroll.contentInset.top)
    }

    private func reportOutside() {
        let centerInScroll = CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY)
        let inCanvas = canvas.convert(centerInScroll, from: scroll)
        let coord = canvas.coordinate(at: inCanvas)
        let west = pack.region.centerLongitude - pack.region.spanLongitude / 2
        let east = pack.region.centerLongitude + pack.region.spanLongitude / 2
        let south = pack.region.centerLatitude - pack.region.spanLatitude / 2
        let north = pack.region.centerLatitude + pack.region.spanLatitude / 2
        let padLon = pack.region.spanLongitude * 0.05
        let padLat = pack.region.spanLatitude * 0.05
        let outside = coord.1 < west - padLon || coord.1 > east + padLon
            || coord.0 < south - padLat || coord.0 > north + padLat
            || scroll.zoomScale < scroll.minimumZoomScale * 1.01
        if outside != lastOutside {
            lastOutside = outside
            coordinator?.onOutsidePack(outside)
        }
    }

    /// Pack bbox + 5%. Does not follow GPS off-pack.
    private func clampCamera() {
        let centerInScroll = CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY)
        let inCanvas = canvas.convert(centerInScroll, from: scroll)
        let coord = canvas.coordinate(at: inCanvas)
        let west = pack.region.west - pack.region.spanLongitude * 0.05
        let east = pack.region.east + pack.region.spanLongitude * 0.05
        let south = pack.region.south - pack.region.spanLatitude * 0.05
        let north = pack.region.north + pack.region.spanLatitude * 0.05
        let lat = min(max(coord.0, south), north)
        let lon = min(max(coord.1, west), east)
        if abs(lat - coord.0) > 1e-9 || abs(lon - coord.1) > 1e-9 {
            centerOn(latitude: lat, longitude: lon)
        }
    }
}

final class TileCanvasLayer: UIView {
    var overlay: BundledTileOverlay?
    var x0 = 0
    var y0 = 0
    var zMax = 12
    var zMin = 10
    var cols = 1
    var rows = 1
    var zoomScale: CGFloat = 1
    var selfFix: LocationFix?
    var manualPin: LocationFix?
    var breadcrumbs: [BreadcrumbRecordDTO] = []
    var viewshed: [ViewshedRay] = []
    var slope: [SlopeSample] = []
    var showViewshed = false
    var viewshedOrigin: LocationFix?
    var showSlope = false
    var routing: RoutingPack?
    var routeLine: [RoutingCoordinate] = []
    var destination: RoutingCoordinate?
    var showPackTiles = true
    var showStreets = false
    var showTopoTiles = false
    var showTrails = false
    var headingDegrees: Double?
    var accuracyMeters: Double?
    var packContainsSelf = false
    var activeManeuver: Maneuver?
    var inboundPing: LocationFix?
    var inboundPingHue: FieldPingHue?
    var searchPattern: [(Double, Double)] = []
    var sharedTrack: [FollowTrackWire.Point] = []
    var amenityPins: [RoutingPOI] = []
    var markPins: [RoutingCoordinate] = []
    private let cache = NSCache<NSString, UIImage>()
    private let duskQueue = DispatchQueue(label: "blackout.map.dusk-remap", qos: .userInitiated)
    private var duskInflight = Set<String>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        if MapChromeLock.duskRemapCachesTiles {
            cache.countLimit = 256
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        if MapChromeLock.daylightStreetsAreBase {
            ctx.setFillColor(
                UIColor(
                    red: MapChromeLock.daylightLandRed,
                    green: MapChromeLock.daylightLandGreen,
                    blue: MapChromeLock.daylightLandBlue,
                    alpha: 1
                ).cgColor
            )
        } else {
            ctx.setFillColor(UIColor(BlackoutDS.Map.land).cgColor)
        }
        ctx.fill(rect)
        let routeInPlay = routeLine.count >= 2 || destination != nil || !markPins.isEmpty
        ctx.setAlpha(CGFloat(MapChromeLock.basemapAlpha(routeInPlay: routeInPlay)))
        let z = currentZoom()
        let factor = pow(2.0, Double(zMax - z))
        let tileSize = CGFloat(256.0 * factor)
        let lowCols = max(1, Int(ceil(Double(cols) / factor)))
        let lowRows = max(1, Int(ceil(Double(rows) / factor)))
        let minX = max(0, Int(floor(rect.minX / tileSize)))
        let maxX = min(lowCols - 1, Int(floor((rect.maxX - 1) / tileSize)))
        let minY = max(0, Int(floor(rect.minY / tileSize)))
        let maxY = min(lowRows - 1, Int(floor((rect.maxY - 1) / tileSize)))
        let shift = zMax - z
        let worldX0 = x0 >> shift
        let worldY0 = y0 >> shift
        if showPackTiles {
            for ty in minY...max(minY, maxY) {
                for tx in minX...max(minX, maxX) {
                    let tileX = worldX0 + tx
                    let tileY = worldY0 + ty
                    let dest = CGRect(x: CGFloat(tx) * tileSize, y: CGFloat(ty) * tileSize, width: tileSize, height: tileSize)
                    if let raw = image(z: z, x: tileX, y: tileY) {
                        let painted: UIImage
                        if showTopoTiles || MapChromeLock.defaultPaintsLabeledUSGS {
                            painted = raw
                        } else {
                            painted = duskAerial(raw, z: z, x: tileX, y: tileY, dest: dest)
                        }
                        painted.draw(in: dest)
                    }
                }
            }
            if MapChromeLock.duskGradesPackTiles {
                // Overlay-only. Multiply + 0.42 void (device 39) crushed rasters to black.
                ctx.setFillColor(
                    UIColor(BlackoutDS.Surface.void)
                        .withAlphaComponent(CGFloat(MapChromeLock.duskGradeAlpha))
                        .cgColor
                )
                ctx.fill(rect)
            }
        }
        if showStreets {
            drawStreets(in: ctx)
        }
        ctx.setAlpha(1)
        drawRoute(in: ctx)
        if showStreets || MapChromeLock.paintsPackLabelOverlayWhenTopoOff {
            drawStreetNames(in: ctx)
        }
        drawTurnChevrons(in: ctx)
        if let destination {
            drawMark(
                LocationFix(latitude: destination.latitude, longitude: destination.longitude),
                color: UIColor(BlackoutDS.Semantic.warn),
                in: ctx
            )
        }
        for pin in markPins {
            drawMark(
                LocationFix(latitude: pin.latitude, longitude: pin.longitude),
                color: UIColor(BlackoutDS.Semantic.warn),
                in: ctx,
                radius: 5
            )
        }
        drawFollowPuck(in: ctx)
        if let manualPin, manualPin.hasCoordinate,
           selfFix?.latitude != manualPin.latitude || selfFix?.longitude != manualPin.longitude {
            drawMark(manualPin, color: UIColor(BlackoutDS.Silver.metal), in: ctx, radius: 5)
        }
        for crumb in breadcrumbs where crumb.hasCoordinate {
            let fix = LocationFix(latitude: crumb.latitude, longitude: crumb.longitude)
            if crumb.estimated {
                drawDashedMark(fix, color: UIColor(red: 197 / 255, green: 205 / 255, blue: 214 / 255, alpha: 0.9), in: ctx)
            } else {
                drawMark(fix, color: UIColor(red: 197 / 255, green: 205 / 255, blue: 214 / 255, alpha: 0.9), in: ctx, radius: 4)
            }
        }
        drawAmenityPins(in: ctx)
        drawPolyline(searchPattern, color: UIColor(BlackoutDS.Semantic.info), dashed: false, in: ctx)
        drawPolyline(sharedTrack.map { ($0.latitude, $0.longitude) }, color: UIColor(BlackoutDS.Red.sun), dashed: true, in: ctx)
        if let inboundPing, inboundPing.hasCoordinate {
            drawPingPip(inboundPing, hue: inboundPingHue ?? .red, in: ctx)
        }
        if showSlope {
            drawSlope(in: ctx)
        }
        if showViewshed, let origin = viewshedOrigin ?? selfFix {
            drawViewshed(from: origin, in: ctx)
        }
    }

    func coordinate(at point: CGPoint) -> (Double, Double) {
        let tileX = Double(x0) + Double(point.x / 256)
        let tileY = Double(y0) + Double(point.y / 256)
        let lat = WebMercator.latitude(tileY: tileY, zoom: zMax)
        let lon = WebMercator.longitude(tileX: tileX, zoom: zMax)
        return (lat, lon)
    }

    func point(for fix: LocationFix) -> CGPoint? {
        guard let lat = fix.latitude, let lon = fix.longitude else { return nil }
        return point(latitude: lat, longitude: lon)
    }

    func point(latitude: Double, longitude: Double) -> CGPoint? {
        let px = (WebMercator.tileX(longitude: longitude, zoom: zMax) - Double(x0)) * 256
        let py = (WebMercator.tileY(latitude: latitude, zoom: zMax) - Double(y0)) * 256
        return CGPoint(x: px, y: py)
    }

    private func pt(_ value: CGFloat) -> CGFloat {
        value / max(zoomScale, 0.05)
    }

    private func drawStreets(in ctx: CGContext) {
        guard let routing else { return }
        let visible = visibleBounds()
        let indexes = routing.grid.edges(in: visible.west, south: visible.south, east: visible.east, north: visible.north)
        var trails: [[RoutingCoordinate]] = []
        var locals: [[RoutingCoordinate]] = []
        var arterials: [[RoutingCoordinate]] = []
        var highways: [[RoutingCoordinate]] = []
        for edgeIndex in indexes {
            let edge = routing.edges[edgeIndex]
            let name = routing.name(for: edge.nameId)
            let klass = RoadLook.classify(edge: edge, name: name)
            let geom = routing.geometries[edgeIndex]
            guard geom.count >= 2 else { continue }
            switch klass {
            case .trail:
                if showTrails { trails.append(geom) }
            case .local:
                locals.append(geom)
            case .arterial:
                arterials.append(geom)
            case .highway:
                highways.append(geom)
            }
        }
        if showTrails {
            stroke(
                trails,
                color: UIColor(BlackoutDS.Map.trail),
                width: pt(1.5),
                dash: [pt(4), pt(3)],
                in: ctx
            )
        }
        if MapChromeLock.daylightStreetsAreBase {
            stroke(locals, color: UIColor(white: 0.78, alpha: 1), width: pt(1.2), in: ctx)
            stroke(arterials, color: UIColor(white: 1, alpha: 1), width: pt(3.2), in: ctx)
            stroke(arterials, color: UIColor(white: 0.72, alpha: 1), width: pt(2), in: ctx)
            stroke(highways, color: UIColor(white: 0.22, alpha: 1), width: pt(6), in: ctx)
            stroke(highways, color: UIColor(red: 0.98, green: 0.84, blue: 0.42, alpha: 1), width: pt(3.5), in: ctx)
        } else {
            stroke(locals, color: UIColor(BlackoutDS.Silver.steel), width: pt(1), in: ctx)
            stroke(arterials, color: UIColor(BlackoutDS.Silver.dim), width: pt(2), in: ctx)
            stroke(highways, color: UIColor(BlackoutDS.Silver.steel), width: pt(5), in: ctx)
            stroke(highways, color: UIColor(BlackoutDS.Silver.edge), width: pt(3), in: ctx)
        }
    }

    private func drawRoute(in ctx: CGContext) {
        guard routeLine.count >= 2 else { return }
        stroke(
            [routeLine],
            color: UIColor(BlackoutDS.Silver.bright),
            width: pt(4),
            in: ctx
        )
    }

    private func drawStreetNames(in ctx: CGContext) {
        guard let routing else { return }
        let visible = visibleBounds()
        let indexes = routing.grid.edges(in: visible.west, south: visible.south, east: visible.east, north: visible.north)
        var seen = Set<UInt32>()
        var labels = 0
        var shields = 0
        for edgeIndex in indexes {
            guard labels < 36 else { break }
            let edge = routing.edges[edgeIndex]
            guard edge.nameId > 0, seen.insert(edge.nameId).inserted,
                  let raw = routing.name(for: edge.nameId) else { continue }
            let klass = RoadLook.classify(edge: edge, name: raw)
            if klass == .trail, !showTrails { continue }
            let geom = routing.geometries[edgeIndex]
            guard !geom.isEmpty else { continue }
            let mid = geom[geom.count / 2]
            guard let p = point(latitude: mid.latitude, longitude: mid.longitude) else { continue }
            if let shield = RoadLook.shieldText(raw), shields < 12 {
                drawShield(shield, at: p, in: ctx)
                shields += 1
                labels += 1
                continue
            }
            let name = RoadLook.displayName(raw)
            let size: CGFloat = (klass == .highway || klass == .arterial) ? BlackoutDS.Map.callout : BlackoutDS.Map.label
            let color = (klass == .highway || klass == .arterial)
                ? UIColor(BlackoutDS.Silver.bright)
                : UIColor(BlackoutDS.Silver.mid)
            drawHaloLabel(name, at: p, size: size, color: color, in: ctx)
            labels += 1
        }
    }

    private func drawHaloLabel(_ text: String, at origin: CGPoint, size: CGFloat, color: UIColor, in ctx: CGContext) {
        let font = UIFont.systemFont(ofSize: pt(size), weight: .medium)
        let halo = UIColor(BlackoutDS.Surface.void).withAlphaComponent(0.80)
        let ns = text as NSString
        let offsets: [CGPoint] = [
            CGPoint(x: -pt(1), y: 0), CGPoint(x: pt(1), y: 0),
            CGPoint(x: 0, y: -pt(1)), CGPoint(x: 0, y: pt(1))
        ]
        for delta in offsets {
            ns.draw(
                at: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y),
                withAttributes: [.font: font, .foregroundColor: halo]
            )
        }
        ns.draw(at: origin, withAttributes: [.font: font, .foregroundColor: color])
        _ = ctx
    }

    private func drawShield(_ text: String, at center: CGPoint, in ctx: CGContext) {
        let side = pt(BlackoutDS.Map.shield)
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        ctx.setFillColor(UIColor(BlackoutDS.Surface.raised).cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(UIColor(BlackoutDS.Silver.edge).cgColor)
        ctx.setLineWidth(pt(1))
        ctx.stroke(rect)
        let font = UIFont.systemFont(ofSize: pt(BlackoutDS.Map.label), weight: .semibold)
        let ns = text as NSString
        let size = ns.size(withAttributes: [.font: font])
        ns.draw(
            at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            withAttributes: [.font: font, .foregroundColor: UIColor(BlackoutDS.Silver.bright)]
        )
    }

    private func drawFollowPuck(in ctx: CGContext) {
        guard packContainsSelf, let selfFix, let origin = point(for: selfFix) else { return }
        let noFix = accuracyMeters == nil
        let opacity: CGFloat = noFix ? 0.38 : 1
        let haloColor: UIColor
        if noFix {
            haloColor = UIColor(BlackoutDS.Silver.steel)
        } else if let accuracyMeters, accuracyMeters >= 15 {
            haloColor = UIColor(BlackoutDS.Semantic.warn)
        } else {
            haloColor = UIColor(BlackoutDS.Semantic.ok)
        }
        let haloRadius: CGFloat
        if let accuracyMeters, !noFix, let lat = selfFix.latitude {
            haloRadius = max(pt(BlackoutDS.Map.puck / 2 + 4), metersToCanvas(accuracyMeters, latitude: lat))
        } else {
            haloRadius = pt(BlackoutDS.Map.puck / 2 + 6)
        }
        ctx.setFillColor(haloColor.withAlphaComponent(0.18 * opacity).cgColor)
        ctx.fillEllipse(in: CGRect(x: origin.x - haloRadius, y: origin.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2))
        let radius = pt(BlackoutDS.Map.puck / 2)
        ctx.setFillColor(UIColor(BlackoutDS.Map.selfDot).withAlphaComponent(opacity).cgColor)
        ctx.fillEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
        ctx.setStrokeColor(UIColor(BlackoutDS.Silver.bright).withAlphaComponent(opacity).cgColor)
        ctx.setLineWidth(pt(2))
        ctx.strokeEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
        if let headingDegrees {
            let blade = pt(BlackoutDS.Map.blade)
            let radians = (headingDegrees - 90) * .pi / 180
            let tip = CGPoint(
                x: origin.x + darwinCos(radians) * (radius + blade),
                y: origin.y + darwinSin(radians) * (radius + blade)
            )
            let left = CGPoint(
                x: origin.x + darwinCos(radians + 2.4) * (blade * 0.45),
                y: origin.y + darwinSin(radians + 2.4) * (blade * 0.45)
            )
            let right = CGPoint(
                x: origin.x + darwinCos(radians - 2.4) * (blade * 0.45),
                y: origin.y + darwinSin(radians - 2.4) * (blade * 0.45)
            )
            ctx.setFillColor(UIColor(BlackoutDS.Silver.bright).withAlphaComponent(opacity).cgColor)
            ctx.beginPath()
            ctx.move(to: tip)
            ctx.addLine(to: left)
            ctx.addLine(to: right)
            ctx.closePath()
            ctx.fillPath()
        }
    }

    private func drawTurnChevrons(in ctx: CGContext) {
        guard let activeManeuver, RoadLook.isActiveTurn(activeManeuver.kind), routeLine.count >= 2 else { return }
        let marks = chevronAnchors()
        guard !marks.isEmpty else { return }
        for (index, item) in marks.enumerated() {
            let live = index == 0
            drawChevron(
                at: item.point,
                heading: item.heading,
                color: UIColor(live ? BlackoutDS.Red.core : BlackoutDS.Silver.bright),
                in: ctx
            )
        }
    }

    private func chevronAnchors() -> [(point: CGPoint, heading: Double)] {
        guard let maneuver = activeManeuver else { return [] }
        var closest = 0
        var best = Double.greatestFiniteMagnitude
        for (index, coord) in routeLine.enumerated() {
            let d = abs(coord.latitude - maneuver.coordinate.latitude) + abs(coord.longitude - maneuver.coordinate.longitude)
            if d < best {
                best = d
                closest = index
            }
        }
        let gap = pt(BlackoutDS.Map.chevronGap)
        var anchors: [(CGPoint, Double)] = []
        var cursor = closest
        var leftover = 0.0
        while cursor > 0, anchors.count < 3 {
            let a = routeLine[cursor]
            let b = routeLine[cursor - 1]
            guard let pa = point(latitude: a.latitude, longitude: a.longitude),
                  let pb = point(latitude: b.latitude, longitude: b.longitude) else {
                cursor -= 1
                continue
            }
            let seg = darwinHypot(pa.x - pb.x, pa.y - pb.y)
            leftover += Double(seg)
            if leftover >= Double(gap) {
                let heading = darwinAtan2(pa.y - pb.y, pa.x - pb.x) * 180 / .pi
                anchors.append((pa, heading))
                leftover = 0
            }
            cursor -= 1
        }
        return anchors
    }

    private func drawChevron(at origin: CGPoint, heading: Double, color: UIColor, in ctx: CGContext) {
        let size = pt(BlackoutDS.Map.chevron)
        let radians = heading * .pi / 180
        func vertex(_ angle: Double, _ length: CGFloat) -> CGPoint {
            CGPoint(
                x: origin.x + darwinCos(radians + angle) * length,
                y: origin.y + darwinSin(radians + angle) * length
            )
        }
        ctx.setFillColor(color.cgColor)
        ctx.beginPath()
        ctx.move(to: vertex(0, size / 2))
        ctx.addLine(to: vertex(2.3, size / 2))
        ctx.addLine(to: vertex(-2.3, size / 2))
        ctx.closePath()
        ctx.fillPath()
    }

    private func stroke(
        _ lines: [[RoutingCoordinate]],
        color: UIColor,
        width: CGFloat,
        dash: [CGFloat] = [],
        in ctx: CGContext
    ) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        if dash.isEmpty {
            ctx.setLineDash(phase: 0, lengths: [])
        } else {
            ctx.setLineDash(phase: 0, lengths: dash)
        }
        for line in lines {
            ctx.beginPath()
            var started = false
            for coord in line {
                guard let p = point(latitude: coord.latitude, longitude: coord.longitude) else { continue }
                if started {
                    ctx.addLine(to: p)
                } else {
                    ctx.move(to: p)
                    started = true
                }
            }
            if started { ctx.strokePath() }
        }
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func metersToCanvas(_ meters: Double, latitude: Double) -> CGFloat {
        guard let origin = selfFix, let lon = origin.longitude,
              let a = point(latitude: latitude, longitude: lon) else { return pt(20) }
        let dest = offset(latitude: latitude, longitude: lon, meters: meters, bearing: 0)
        guard let b = point(latitude: dest.0, longitude: dest.1) else { return pt(20) }
        return darwinHypot(b.x - a.x, b.y - a.y)
    }

    private func visibleBounds() -> (west: Double, south: Double, east: Double, north: Double) {
        let nw = coordinate(at: bounds.origin)
        let se = coordinate(at: CGPoint(x: bounds.maxX, y: bounds.maxY))
        return (
            west: min(nw.1, se.1),
            south: min(nw.0, se.0),
            east: max(nw.1, se.1),
            north: max(nw.0, se.0)
        )
    }

    private func drawSlope(in ctx: CGContext) {
        for sample in slope {
            let fix = LocationFix(latitude: sample.latitude, longitude: sample.longitude)
            guard let point = point(for: fix) else { continue }
            let t = min(1, sample.degrees / 45)
            ctx.setFillColor(UIColor(red: t, green: 0.2, blue: 0.15, alpha: 0.22).cgColor)
            ctx.fill(CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
        }
    }

    private func drawViewshed(from origin: LocationFix, in ctx: CGContext) {
        guard let start = point(for: origin), origin.hasCoordinate else { return }
        ctx.setFillColor(UIColor(red: 197 / 255, green: 205 / 255, blue: 214 / 255, alpha: 0.12).cgColor)
        ctx.beginPath()
        ctx.move(to: start)
        for ray in viewshed {
            let dest = offset(latitude: origin.latitude!, longitude: origin.longitude!, meters: ray.visibleMeters, bearing: ray.bearingDegrees)
            let fix = LocationFix(latitude: dest.0, longitude: dest.1)
            if let p = point(for: fix) {
                ctx.addLine(to: p)
            }
        }
        ctx.closePath()
        ctx.fillPath()
        ctx.setStrokeColor(UIColor(red: 197 / 255, green: 205 / 255, blue: 214 / 255, alpha: 0.45).cgColor)
        ctx.setLineWidth(1)
        ctx.beginPath()
        ctx.move(to: start)
        for ray in viewshed {
            let dest = offset(latitude: origin.latitude!, longitude: origin.longitude!, meters: ray.visibleMeters, bearing: ray.bearingDegrees)
            let fix = LocationFix(latitude: dest.0, longitude: dest.1)
            if let p = point(for: fix) {
                ctx.addLine(to: p)
            }
        }
        ctx.closePath()
        ctx.strokePath()
    }

    private func offset(latitude: Double, longitude: Double, meters: Double, bearing: Double) -> (Double, Double) {
        let r = 6_371_000.0
        let brng = bearing * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = Darwin.asin(
            Darwin.sin(lat1) * Darwin.cos(meters / r)
                + Darwin.cos(lat1) * Darwin.sin(meters / r) * Darwin.cos(brng)
        )
        let lon2 = lon1 + Darwin.atan2(
            Darwin.sin(brng) * Darwin.sin(meters / r) * Darwin.cos(lat1),
            Darwin.cos(meters / r) - Darwin.sin(lat1) * Darwin.sin(lat2)
        )
        return (lat2 * 180 / .pi, lon2 * 180 / .pi)
    }

    private func drawAmenityPins(in ctx: CGContext) {
        let visible = PackAmenityPolicy.visiblePins(pois: amenityPins, zoom: currentZoom())
        for poi in visible {
            let color: UIColor
            if poi.kind == "hospital" {
                color = UIColor(BlackoutDS.Semantic.warn)
            } else if poi.kind == "water" || poi.kind == "spring" || poi.kind == "tank" {
                color = UIColor(BlackoutDS.Semantic.info)
            } else {
                color = UIColor(BlackoutDS.Silver.metal)
            }
            drawMark(
                LocationFix(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude),
                color: color,
                in: ctx,
                radius: 4
            )
        }
    }

    private func drawMark(_ fix: LocationFix?, color: UIColor, in ctx: CGContext, radius: CGFloat = 7) {
        guard let fix, let point = point(for: fix) else { return }
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }

    private func drawDashedMark(_ fix: LocationFix?, color: UIColor, in ctx: CGContext) {
        guard let fix, let point = point(for: fix) else { return }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(pt(2))
        ctx.setLineDash(phase: 0, lengths: [pt(3), pt(3)])
        ctx.strokeEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func drawPolyline(_ coords: [(Double, Double)], color: UIColor, dashed: Bool, in ctx: CGContext) {
        let points = coords.compactMap { point(latitude: $0.0, longitude: $0.1) }
        guard points.count >= 2 else { return }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(pt(2))
        if dashed {
            ctx.setLineDash(phase: 0, lengths: [pt(6), pt(4)])
        }
        ctx.beginPath()
        ctx.move(to: points[0])
        for p in points.dropFirst() {
            ctx.addLine(to: p)
        }
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func drawPingPip(_ fix: LocationFix, hue: FieldPingHue, in ctx: CGContext) {
        guard let point = point(for: fix) else { return }
        let color: UIColor
        switch hue {
        case .ok: color = UIColor(BlackoutDS.Semantic.ok)
        case .warn: color = UIColor(BlackoutDS.Semantic.warn)
        case .red: color = UIColor(BlackoutDS.Red.core)
        }
        let radius: CGFloat = 8
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(pt(3))
        ctx.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        ctx.setFillColor(color.withAlphaComponent(0.35).cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
    }

    func currentZoom() -> Int {
        let z = zMax + Int(floor(log2(Double(max(zoomScale, 0.01)))))
        return min(zMax, max(zMin, z))
    }

    private func image(z: Int, x: Int, y: Int) -> UIImage? {
        let key = "\(z)/\(x)/\(y)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = overlay?.tileData(z: z, x: x, y: y), let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private func duskAerial(_ source: UIImage, z: Int, x: Int, y: Int, dest: CGRect) -> UIImage {
        guard MapChromeLock.remapsLabeledPackTilesToDuskAerial else { return source }
        let key = "dusk/\(z)/\(x)/\(y)" as NSString
        if MapChromeLock.duskRemapCachesTiles, let cached = cache.object(forKey: key) {
            return cached
        }
        if MapChromeLock.duskRemapBlocksDraw {
            guard let painted = Self.remappedDuskAerial(source) else { return source }
            if MapChromeLock.duskRemapCachesTiles {
                cache.setObject(painted, forKey: key)
            }
            return painted
        }
        enqueueDuskRemap(source, key: key, dest: dest)
        return source
    }

    private func enqueueDuskRemap(_ source: UIImage, key: NSString, dest: CGRect) {
        let token = key as String
        guard duskInflight.insert(token).inserted else { return }
        duskQueue.async { [weak self] in
            let painted = Self.remappedDuskAerial(source)
            DispatchQueue.main.async {
                guard let self else { return }
                self.duskInflight.remove(token)
                if let painted {
                    if MapChromeLock.duskRemapCachesTiles {
                        self.cache.setObject(painted, forKey: key)
                    }
                    self.setNeedsDisplay(dest)
                }
            }
        }
    }

    private static func remappedDuskAerial(_ source: UIImage) -> UIImage? {
        guard let cg = source.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return nil }
            guard let ctx = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            let count = height * bytesPerRow
            var index = 0
            while index + 3 < count {
                let lum = (
                    0.2126 * Double(ptr[index])
                        + 0.7152 * Double(ptr[index + 1])
                        + 0.0722 * Double(ptr[index + 2])
                ) / 255.0
                let rgb = MapChromeLock.duskAerialRGB(tileLuminance: lum)
                ptr[index] = UInt8((rgb.0 * 255).clamped(to: 0...255))
                ptr[index + 1] = UInt8((rgb.1 * 255).clamped(to: 0...255))
                ptr[index + 2] = UInt8((rgb.2 * 255).clamped(to: 0...255))
                index += 4
            }
            guard let out = ctx.makeImage() else { return nil }
            return UIImage(cgImage: out)
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
