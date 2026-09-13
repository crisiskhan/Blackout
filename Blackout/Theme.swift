import SwiftUI
import Tokens
import NightRed

enum Theme {
    static var void: Color { Color(rgba: BlackoutTokens.Color.void) }
    static var accent: Color { Color(rgba: BlackoutTokens.Color.accent) }
    static var silver: Color { Color(rgba: BlackoutTokens.Color.silver) }
    static var raised: Color { Color(rgba: BlackoutTokens.Color.raised) }
    static var warn: Color { Color(rgba: BlackoutTokens.Color.warn) }
    static var caution: Color { Color(rgba: BlackoutTokens.Color.caution) }
    static var heat: Color { Color(rgba: BlackoutTokens.Color.heat) }
    static var nightRed: Color { Color(rgba: BlackoutTokens.Color.nightRed) }
    static var fix: Color { Color(rgba: BlackoutTokens.Color.fix) }
    static var metalHigh: Color { Color(rgba: BlackoutTokens.Color.metalHighlight) }
    static var metalLow: Color { Color(rgba: BlackoutTokens.Color.metalShade) }
    static var plateCorner: CGFloat { CGFloat(BlackoutTokens.Chrome.hudPlateCornerPoints) }

    enum Motion {
        static var sleep: Animation {
            .easeInOut(duration: BlackoutTokens.Chrome.chromeSleepSeconds)
        }
        static var wake: Animation {
            .easeOut(duration: BlackoutTokens.Chrome.chromeWakeSeconds)
        }
        static var heavy: Animation {
            .easeInOut(duration: BlackoutTokens.Chrome.chromeSleepSeconds)
        }
        static var beat: Animation {
            .easeInOut(duration: BlackoutTokens.Chrome.destChipBeatSeconds)
                .repeatForever(autoreverses: true)
        }
    }

    static func plateRect() -> RoundedRectangle {
        RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
    }

    static var metalStroke: LinearGradient {
        LinearGradient(
            colors: [metalHigh, silver, metalLow],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Faceted metal plate on void. No iOS blur — streets stay under the type.
    static func glass(opacity: Double = 0.88) -> some View {
        ZStack {
            Rectangle().fill(void.opacity(opacity))
            LinearGradient(
                colors: [
                    metalHigh.opacity(0.22),
                    Color.clear,
                    metalLow.opacity(0.58),
                ],
                startPoint: UnitPoint(x: 0.04, y: 0.0),
                endPoint: UnitPoint(x: 0.96, y: 1.0)
            )
            LinearGradient(
                colors: [
                    Color.clear,
                    metalHigh.opacity(0.11),
                    Color.clear,
                ],
                startPoint: UnitPoint(x: 0.0, y: 0.30),
                endPoint: UnitPoint(x: 1.0, y: 0.70)
            )
        }
    }
}

/// Long-wavelength lamp. Multiply keeps void void and leaves accent on red.
/// Always on the tree so toggling it cannot unmount MapLibre.
private struct NightRedLamp: ViewModifier {
    var night: NightRedState

    func body(content: Content) -> some View {
        content
            .colorMultiply(night.enabled ? Theme.nightRed : Color.white)
            .brightness(night.enabled ? NightRedState.dim : 0)
    }
}

extension View {
    func nightRedLamp(_ night: NightRedState) -> some View {
        modifier(NightRedLamp(night: night))
    }
}

extension Color {
    init(rgba: BlackoutTokens.RGBA) {
        self.init(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}

/// Double metal ring. Stroke only — the well stays empty.
struct HUDRing: View {
    var diameter: CGFloat
    var lit: Bool = false

    var body: some View {
        let ink = lit ? Theme.accent : Theme.silver
        ZStack {
            Circle()
                .strokeBorder(Theme.metalStroke, lineWidth: 1.7)
            Circle()
                .strokeBorder(ink.opacity(lit ? 0.95 : 0.34), lineWidth: 1)
                .padding(3)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: lit ? Theme.accent.opacity(0.55) : Color.clear, radius: lit ? 9 : 0)
        .accessibilityHidden(true)
    }
}

/// The product mark on the glass. Same compass as the App Icon and boot.
struct HUDMark: View {
    var points: Double = BlackoutTokens.Chrome.hudMarkPoints

    var body: some View {
        let size = CGFloat(points)
        ZStack {
            HUDRing(diameter: size + 8)
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// The logo's center, as a selected-tab tick. Not a random underline.
/// Lit is HUD red. The frame stays the reticle size — glow is light, not layout.
struct HUDReticle: View {
    var lit: Bool
    var crisis: Bool = false
    @State private var beat: Double = 0.28

    var body: some View {
        let ink = lit ? Theme.accent : Color.clear
        let size = CGFloat(BlackoutTokens.Chrome.hudReticlePoints)
        let pulse = lit ? beat : 0
        let glow = (crisis ? 0.42 : 0.28) + 0.58 * pulse
        let radius = (crisis ? 6.0 : 4.0) + (crisis ? 8.0 : 6.0) * pulse
        return ZStack {
            Circle()
                .stroke(ink, lineWidth: 1)
            Circle()
                .stroke(ink.opacity(0.45), lineWidth: 1)
                .padding(2)
            Rectangle()
                .fill(ink)
                .frame(width: size, height: 1)
            Rectangle()
                .fill(ink)
                .frame(width: 1, height: size)
        }
        .frame(width: size, height: size)
        .shadow(color: ink.opacity(glow), radius: radius)
        .shadow(color: ink.opacity(glow * 0.55), radius: radius * 1.6)
        .accessibilityHidden(true)
        .onChange(of: lit) { _, now in
            beat = 0.28
            guard now else { return }
            withAnimation(Theme.Motion.beat) { beat = 1 }
        }
        .onAppear {
            guard lit else { return }
            withAnimation(Theme.Motion.beat) { beat = 1 }
        }
    }
}

/// Full-width 44pt dock cell. Equal split, no tail-ellipsis.
struct HUDDockStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let hit = BlackoutTokens.Chrome.mapChipHitPoints
        return configuration.label
            .font(.system(size: 12, weight: .heavy))
            .lineLimit(2)
            .minimumScaleFactor(1)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: hit, maxHeight: hit)
            .contentShape(Rectangle())
            .foregroundStyle(Theme.silver)
            .background(Theme.glass(opacity: configuration.isPressed ? 0.55 : 0.92))
            .clipShape(Theme.plateRect())
            .overlay(
                Theme.plateRect()
                    .strokeBorder(Theme.metalStroke, lineWidth: 1)
            )
    }
}

/// Overlay chip that keeps its whole word. Used for INSTRUMENTS and LOCK-ON.
struct HUDOverlayChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let hit = BlackoutTokens.Chrome.mapChipHitPoints
        return configuration.label
            .font(.system(size: BlackoutTokens.Chrome.mapActionChipTextPoints, weight: .heavy))
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, BlackoutTokens.Chrome.mapActionChipGutterPoints)
            .frame(minWidth: hit, minHeight: hit)
            .contentShape(Rectangle())
            .foregroundStyle(Theme.silver)
            .background(Theme.glass())
            .clipShape(Theme.plateRect())
            .overlay(
                Theme.plateRect()
                    .strokeBorder(Theme.metalStroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// Dest-slot chips on MAP. TURNS still uses the lamp. COORDINATES
/// are the green numbers on void — no word in a box over the map.
struct MapFieldDestChipStyle: ButtonStyle {
    var ink: Color
    var expanded: Bool
    var beat: Double

    func makeBody(configuration: Configuration) -> some View {
        let hit = BlackoutTokens.Chrome.mapChipHitPoints
        let pulse = expanded ? beat : 0.45 * beat
        let glow = 0.28 + 0.62 * pulse
        let radius = (expanded ? 12.0 : 7.0) + (expanded ? 12.0 : 7.0) * pulse
        return configuration.label
            .font(.system(size: BlackoutTokens.Chrome.mapActionChipTextPoints, weight: .heavy))
            .minimumScaleFactor(1)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, BlackoutTokens.Chrome.mapActionChipGutterPoints)
            .frame(minWidth: hit, minHeight: hit, maxHeight: hit, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(ink)
            .overlay(
                Theme.plateRect()
                    .strokeBorder(ink.opacity(0.48 + 0.52 * pulse), lineWidth: expanded ? 2 : 1.2)
            )
            .shadow(color: Theme.void.opacity(0.9), radius: 2, x: 0, y: 0)
            .shadow(color: ink.opacity(glow), radius: radius, x: 0, y: 0)
            .shadow(color: ink.opacity(glow * 0.55), radius: radius * 1.7, x: 0, y: 0)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// Status ink on a HUD page. Silver is idle, warn is honesty chrome, go is
/// CONDITION GREEN, caution is CONDITION YELLOW, heat is CONDITION ORANGE,
/// crisis is RED, sos is CONDITION BLACK.
enum HUDStatusTone: Sendable, Equatable {
    case silver
    case warn
    case go
    case caution
    case heat
    case crisis
    case sos

    var ink: Color {
        switch self {
        case .silver: return Theme.silver
        case .warn: return Theme.warn
        case .go: return Theme.fix
        case .caution: return Theme.caution
        case .heat: return Theme.heat
        case .crisis: return Theme.accent
        case .sos: return Color.white
        }
    }

    var crisis: Bool {
        switch self {
        case .crisis, .sos: return true
        case .silver, .warn, .go, .caution, .heat: return false
        }
    }
}

/// Glass page over the still-mounted map. COMMS / FIELD / EXPEDITION speak
/// this language so they are not a form dump next to a HUD.
struct HUDPage<Content: View>: View {
    let title: String
    var status: String = ""
    var statusTone: HUDStatusTone = .silver
    var content: Content

    init(
        title: String,
        status: String = "",
        statusTone: HUDStatusTone = .silver,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.status = status
        self.statusTone = statusTone
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    HUDRing(diameter: 30, lit: statusTone.crisis)
                    HUDMark()
                }
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                Spacer(minLength: 8)
                if !status.isEmpty {
                    Text(status)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusTone.ink)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.glass(opacity: 0.86))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.metalStroke)
                .frame(height: 1)
        }
    }
}

struct HUDGlassCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.glass())
            .clipShape(Theme.plateRect())
            .overlay(
                Theme.plateRect()
                    .strokeBorder(Theme.metalStroke, lineWidth: 1)
            )
    }
}

struct HUDActionStyle: ButtonStyle {
    var filled: Bool
    var crisis: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(filled ? Color.white : Theme.silver)
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            .contentShape(Rectangle())
            .background(
                Group {
                    if filled && crisis {
                        Theme.accent
                    } else {
                        Theme.glass(opacity: configuration.isPressed ? 0.5 : 0.92)
                    }
                }
            )
            .overlay {
                if filled && crisis {
                    Theme.plateRect()
                        .strokeBorder(Theme.accent, lineWidth: 1.5)
                } else {
                    Theme.plateRect()
                        .strokeBorder(Theme.metalStroke, lineWidth: 1)
                }
            }
            .clipShape(Theme.plateRect())
            .shadow(
                color: Theme.accent.opacity(filled && crisis ? 0.42 : 0),
                radius: filled && crisis ? 10 : 0
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// Left-aligned rail that moves a control to the next line when the current one is full.
/// INSTRUMENTS never becomes INST, and it never becomes INSTRUME….
struct HUDWrapRail: Layout {
    var spacing: CGFloat

    init(spacing: Double) {
        self.spacing = CGFloat(spacing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = rowsFitting(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in rowsFitting(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rowsFitting(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, width > maxWidth {
                rows.append(row)
                row = Row(indices: [index], width: size.width, height: size.height)
            } else {
                row.indices.append(index)
                row.width = width
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
