import AudioToolbox
import BlackoutCore
import DesignSystem
import SwiftUI
import UIKit

/// Polar HUD on top of the file-tile map. Transparent — never a black disc.
/// Wave 1.5: 0 peers. Members would be filled silver disks; strangers hollow rings.
struct RadarHUDView: View {
    var headingUp: Bool
    var headingDegrees: Double?
    var peers: [RadarBlip]
    var sweepAudio: Bool
    var onSelectPeer: (RadarBlip) -> Void
    var onSelectSelf: () -> Void

    @State private var lastHapticIDs: Set<BlackoutID> = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let sweep = sweepAngle(at: timeline.date)
            ZStack {
                RadarPolarCanvas(
                    sweepAngle: sweep,
                    peers: peers,
                    headingDegrees: headingUp ? 0 : (headingDegrees ?? 0)
                )
                .allowsHitTesting(false)
                Button(action: onSelectSelf) {
                    Circle()
                        .fill(BlackoutDS.Silver.metal)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(BlackoutDS.Semantic.info, lineWidth: 2))
                        .shadow(color: BlackoutDS.Red.core.opacity(0.35), radius: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Self. Not a peer.")
                ForEach(peers) { blip in
                    peerMark(blip)
                }
            }
            .onChange(of: sweep) { _, angle in
                hapticIfSweepHits(angle)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func peerMark(_ blip: RadarBlip) -> some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) * 0.42
            let rangeFrac = min(1, blip.rangeMeters / 3_000)
            let screenBearing = blip.bearingDegrees - (headingUp ? (headingDegrees ?? 0) : 0)
            let rad = (screenBearing - 90) * .pi / 180
            let r = radius * rangeFrac
            let x = geo.size.width / 2 + cos(rad) * r
            let y = geo.size.height / 2 + sin(rad) * r
            Button {
                onSelectPeer(blip)
            } label: {
                Circle()
                    .fill(pipFill(blip))
                    .overlay(
                        Circle().stroke(pipStroke(blip), lineWidth: 2)
                    )
                    .frame(width: 16, height: 16)
            }
            .position(x: x, y: y)
        }
        .allowsHitTesting(true)
    }

    private func pipFill(_ blip: RadarBlip) -> Color {
        switch blip.band {
        case .red:
            return BlackoutDS.Red.core
        case .yellow:
            return BlackoutDS.Semantic.warn
        case .green:
            switch blip.kind {
            case .member, .selfDot:
                return BlackoutDS.Silver.metal
            case .stranger:
                return Color.clear
            }
        }
    }

    private func pipStroke(_ blip: RadarBlip) -> Color {
        switch blip.band {
        case .red:
            return BlackoutDS.Red.hot
        case .yellow, .green:
            return BlackoutDS.Silver.edge
        }
    }

    private func sweepAngle(at date: Date) -> Double {
        let period = 3.0
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return t / period * 360
    }

    private func hapticIfSweepHits(_ angle: Double) {
        var hit: Set<BlackoutID> = []
        for blip in peers {
            let screenBearing = blip.bearingDegrees - (headingUp ? (headingDegrees ?? 0) : 0)
            let norm = (screenBearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            let delta = abs(norm - angle)
            let wrapped = min(delta, 360 - delta)
            if wrapped < 8 {
                hit.insert(blip.id)
                if !lastHapticIDs.contains(blip.id) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if sweepAudio {
                        RadarSweepClick.play()
                    }
                }
            }
        }
        lastHapticIDs = hit
        if sweepAudio, peers.isEmpty {
            // Default OFF. Empty sweep is silent even if the user later enables audio.
        }
    }
}

struct RadarPolarCanvas: View {
    var sweepAngle: Double
    var peers: [RadarBlip]
    var headingDegrees: Double

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.42
            _ = headingDegrees
            let void = Color(red: 7 / 255, green: 8 / 255, blue: 10 / 255)
            _ = void
            for i in 1...3 {
                var ring = Path()
                ring.addEllipse(in: CGRect(
                    x: center.x - radius * CGFloat(i) / 3,
                    y: center.y - radius * CGFloat(i) / 3,
                    width: radius * 2 * CGFloat(i) / 3,
                    height: radius * 2 * CGFloat(i) / 3
                ))
                ctx.stroke(
                    ring,
                    with: .color(BlackoutDS.Silver.edge.opacity(0.35)),
                    lineWidth: 1
                )
            }
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - radius, y: center.y))
            cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: center.y - radius))
            cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            ctx.stroke(cross, with: .color(BlackoutDS.Silver.edge.opacity(0.2)), lineWidth: 0.5)

            let start = (sweepAngle - 28 - 90) * .pi / 180
            let end = (sweepAngle - 90) * .pi / 180
            var wedge = Path()
            wedge.move(to: center)
            wedge.addArc(center: center, radius: radius, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
            wedge.closeSubpath()
            ctx.fill(wedge, with: .linearGradient(
                Gradient(colors: [
                    BlackoutDS.Red.core.opacity(0.0),
                    BlackoutDS.Red.hot.opacity(0.28)
                ]),
                startPoint: center,
                endPoint: CGPoint(
                    x: center.x + cos(end) * radius,
                    y: center.y + sin(end) * radius
                )
            ))
            var beam = Path()
            beam.move(to: center)
            beam.addLine(to: CGPoint(
                x: center.x + cos(end) * radius,
                y: center.y + sin(end) * radius
            ))
            ctx.stroke(beam, with: .color(BlackoutDS.Red.core.opacity(0.85)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}

enum RadarSweepClick {
    static func play() {
        AudioServicesPlaySystemSound(1104)
    }
}

/// Peer sheet. Message + Navigate-to. Tap self does not present this.
struct RadarPeerSheet: View {
    var blip: RadarBlip
    var onMessage: () -> Void
    var onNavigate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(
                blip.displayName ?? Callsign.defaultValue,
                subtitle: subtitle
            )
            if let footnote = blip.footnote {
                Text(footnote)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
            }
            HUDPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ping age: \(blip.pingAge.map { "\(Int($0))s" } ?? "—")")
                    Text("Hops: \(blip.hops.map(String.init) ?? "—")")
                    Text(String(format: "Range %.0f m  ·  %d°", blip.rangeMeters, Int(blip.bearingDegrees)))
                    if blip.band == .red {
                        Text(PartyVitalsCopy.imNot)
                            .foregroundStyle(BlackoutDS.Red.hot)
                    }
                    if blip.latitude == nil || blip.longitude == nil {
                        Text("No GPS for this peer.")
                            .foregroundStyle(BlackoutDS.Silver.dim)
                    }
                    if blip.isUnknown {
                        Text("No vitals for unknown.")
                            .foregroundStyle(BlackoutDS.Silver.dim)
                    }
                }
            }
            MetalButton(PartyVitalsCopy.message, height: BlackoutDS.Hit.sm, action: onMessage)
            MetalButton(PartyVitalsCopy.navigateTo, height: BlackoutDS.Hit.md, action: onNavigate)
            Spacer()
        }
        .padding(20)
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var subtitle: String {
        switch blip.kind {
        case .member:
            return blip.band == .red ? "Member · red" : "Member · filled disk"
        case .stranger:
            return "Stranger · hollow ring"
        case .selfDot:
            return "Self. Not a peer."
        }
    }
}
