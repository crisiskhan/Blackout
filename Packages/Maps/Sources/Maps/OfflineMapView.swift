import BlackoutCore
import DesignSystem
import MapsRouting
import SwiftUI
import UIKit

/// File-tile map. Does **not** create MKMapView, so Apple raster/CDN is not on first paint.
struct OfflineMapView: UIViewRepresentable {
    var pack: MapPackSnapshot
    var selfFix: LocationFix?
    var manualPin: LocationFix?
    var breadcrumbs: [BreadcrumbRecordDTO]
    var viewshed: [ViewshedRay]
    var slope: [SlopeSample]
    var showViewshed: Bool
    var showSlope: Bool
    var centerToken: Int
    /// When true, Recenter pinned the camera to pack coverage. GPS follow
    /// (El Paso 31.87,-106.60 etc.) must not yank the camera off Denver tiles.
    var pinCameraToPack: Bool
    var routing: RoutingPack?
    var routeLine: [RoutingCoordinate]
    var destination: RoutingCoordinate?
    var showPackTiles: Bool
    var showTrails: Bool
    var headingDegrees: Double?
    var accuracyMeters: Double?
    var packContainsSelf: Bool
    var activeManeuver: Maneuver?
    var onDropPin: (Double, Double) -> Void
    var onTap: ((Double, Double) -> Void)?
    var onOutsidePack: (Bool) -> Void
    var resetToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(onDropPin: onDropPin, onTap: onTap, onOutsidePack: onOutsidePack)
    }

    func makeUIView(context: Context) -> OfflineTileScrollView {
        let view = OfflineTileScrollView(pack: pack)
        view.coordinator = context.coordinator
        view.applyOverlays(
            selfFix: selfFix,
            manualPin: manualPin,
            breadcrumbs: breadcrumbs,
            viewshed: viewshed,
            slope: slope,
            showViewshed: showViewshed,
            showSlope: showSlope,
            routing: routing,
            routeLine: routeLine,
            destination: destination,
            showPackTiles: showPackTiles,
            showTrails: showTrails,
            headingDegrees: headingDegrees,
            accuracyMeters: accuracyMeters,
            packContainsSelf: packContainsSelf,
            activeManeuver: activeManeuver
        )
        return view
    }

    func updateUIView(_ view: OfflineTileScrollView, context: Context) {
        context.coordinator.onDropPin = onDropPin
        context.coordinator.onTap = onTap
        context.coordinator.onOutsidePack = onOutsidePack
        view.coordinator = context.coordinator
        view.applyOverlays(
            selfFix: selfFix,
            manualPin: manualPin,
            breadcrumbs: breadcrumbs,
            viewshed: viewshed,
            slope: slope,
            showViewshed: showViewshed,
            showSlope: showSlope,
            routing: routing,
            routeLine: routeLine,
            destination: destination,
            showPackTiles: showPackTiles,
            showTrails: showTrails,
            headingDegrees: headingDegrees,
            accuracyMeters: accuracyMeters,
            packContainsSelf: packContainsSelf,
            activeManeuver: activeManeuver
        )
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            view.recenterToPackCoverage()
        }
        if context.coordinator.lastCenterToken != centerToken {
            context.coordinator.lastCenterToken = centerToken
            // Heading-up / "center on me" only. Recenter to pack coverage
            // never uses this path — GPS outside the sample paints void.
            if !pinCameraToPack, let selfFix, selfFix.hasCoordinate {
                view.centerOn(latitude: selfFix.latitude!, longitude: selfFix.longitude!)
            }
        }
    }

    final class Coordinator {
        var onDropPin: (Double, Double) -> Void
        var onTap: ((Double, Double) -> Void)?
        var onOutsidePack: (Bool) -> Void
        var lastResetToken = 0
        var lastCenterToken = 0

        init(
            onDropPin: @escaping (Double, Double) -> Void,
            onTap: ((Double, Double) -> Void)?,
            onOutsidePack: @escaping (Bool) -> Void
        ) {
            self.onDropPin = onDropPin
            self.onTap = onTap
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
        backgroundColor = UIColor(red: 7 / 255, green: 8 / 255, blue: 10 / 255, alpha: 1)
        scroll.delegate = self
        scroll.backgroundColor = backgroundColor
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bounces = true
        scroll.bouncesZoom = true
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
    }

    func recenterToPackCoverage() {
        let fit = min(
            bounds.width / max(canvas.bounds.width, 1),
            bounds.height / max(canvas.bounds.height, 1)
        )
        scroll.minimumZoomScale = min(0.2, max(fit * 0.5, 0.05))
        scroll.setZoomScale(max(fit, scroll.minimumZoomScale), animated: false)
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
        showSlope: Bool,
        routing: RoutingPack?,
        routeLine: [RoutingCoordinate],
        destination: RoutingCoordinate?,
        showPackTiles: Bool,
        showTrails: Bool,
        headingDegrees: Double?,
        accuracyMeters: Double?,
        packContainsSelf: Bool,
        activeManeuver: Maneuver?
    ) {
        canvas.selfFix = selfFix
        canvas.manualPin = manualPin
        canvas.breadcrumbs = breadcrumbs
        canvas.viewshed = viewshed
        canvas.slope = slope
        canvas.showViewshed = showViewshed
        canvas.showSlope = showSlope
        canvas.routing = routing
        canvas.routeLine = routeLine
        canvas.destination = destination
        canvas.showPackTiles = showPackTiles
        canvas.showTrails = showTrails
        canvas.headingDegrees = headingDegrees
        canvas.accuracyMeters = accuracyMeters
        canvas.packContainsSelf = packContainsSelf
        canvas.activeManeuver = activeManeuver
        canvas.setNeedsDisplay()
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

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        canvas.zoomScale = scrollView.zoomScale
        canvas.setNeedsDisplay()
        clampCamera()
        reportOutside()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        canvas.zoomScale = scrollView.zoomScale
        canvas.setNeedsDisplay()
        clampCamera()
        reportOutside()
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: canvas)
        let lonlat = canvas.coordinate(at: point)
        coordinator?.onDropPin(lonlat.0, lonlat.1)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: canvas)
        let lonlat = canvas.coordinate(at: point)
        coordinator?.onTap?(lonlat.0, lonlat.1)
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
    var showSlope = false
    var routing: RoutingPack?
    var routeLine: [RoutingCoordinate] = []
    var destination: RoutingCoordinate?
    var showPackTiles = true
    var showTrails = false
    var headingDegrees: Double?
    var accuracyMeters: Double?
    var packContainsSelf = false
    var activeManeuver: Maneuver?
    private let cache = NSCache<NSString, UIImage>()

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor(BlackoutDS.Map.land).cgColor)
        ctx.fill(rect)
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
                    if let image = image(z: z, x: tileX, y: tileY) {
                        image.draw(in: dest)
                    }
                }
            }
        }
        drawStreets(in: ctx)
        drawRoute(in: ctx)
        drawStreetNames(in: ctx)
        drawTurnChevrons(in: ctx)
        if let destination {
            drawMark(
                LocationFix(latitude: destination.latitude, longitude: destination.longitude),
                color: UIColor(BlackoutDS.Semantic.warn),
                in: ctx
            )
        }
        drawFollowPuck(in: ctx)
        if let manualPin, manualPin.hasCoordinate,
           selfFix?.latitude != manualPin.latitude || selfFix?.longitude != manualPin.longitude {
            drawMark(manualPin, color: UIColor(BlackoutDS.Silver.metal), in: ctx, radius: 5)
        }
        for crumb in breadcrumbs where crumb.hasCoordinate {
            let fix = LocationFix(latitude: crumb.latitude, longitude: crumb.longitude)
            drawMark(fix, color: UIColor(red: 197 / 255, green: 205 / 255, blue: 214 / 255, alpha: 0.9), in: ctx, radius: 4)
        }
        if showSlope {
            drawSlope(in: ctx)
        }
        if showViewshed, let selfFix {
            drawViewshed(from: selfFix, in: ctx)
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
        stroke(locals, color: UIColor(BlackoutDS.Silver.steel), width: pt(1), in: ctx)
        stroke(arterials, color: UIColor(BlackoutDS.Silver.dim), width: pt(2), in: ctx)
        stroke(highways, color: UIColor(BlackoutDS.Silver.steel), width: pt(5), in: ctx)
        stroke(highways, color: UIColor(BlackoutDS.Silver.edge), width: pt(3), in: ctx)
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
            let tip = CGPoint(x: origin.x + cos(radians) * (radius + blade), y: origin.y + sin(radians) * (radius + blade))
            let left = CGPoint(
                x: origin.x + cos(radians + 2.4) * (blade * 0.45),
                y: origin.y + sin(radians + 2.4) * (blade * 0.45)
            )
            let right = CGPoint(
                x: origin.x + cos(radians - 2.4) * (blade * 0.45),
                y: origin.y + sin(radians - 2.4) * (blade * 0.45)
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
            let seg = hypot(pa.x - pb.x, pa.y - pb.y)
            leftover += seg
            if leftover >= gap {
                let heading = atan2(pa.y - pb.y, pa.x - pb.x) * 180 / .pi
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
            CGPoint(x: origin.x + cos(radians + angle) * length, y: origin.y + sin(radians + angle) * length)
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
        return hypot(b.x - a.x, b.y - a.y)
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
        let lat2 = asin(sin(lat1) * cos(meters / r) + cos(lat1) * sin(meters / r) * cos(brng))
        let lon2 = lon1 + atan2(
            sin(brng) * sin(meters / r) * cos(lat1),
            cos(meters / r) - sin(lat1) * sin(lat2)
        )
        return (lat2 * 180 / .pi, lon2 * 180 / .pi)
    }

    private func drawMark(_ fix: LocationFix?, color: UIColor, in ctx: CGContext, radius: CGFloat = 7) {
        guard let fix, let point = point(for: fix) else { return }
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }

    private func currentZoom() -> Int {
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
}
