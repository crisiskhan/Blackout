import SwiftUI
import Tokens

enum Theme {
    static var void: Color { Color(rgba: BlackoutTokens.Color.void) }
    static var accent: Color { Color(rgba: BlackoutTokens.Color.accent) }
    static var silver: Color { Color(rgba: BlackoutTokens.Color.silver) }
    static var raised: Color { Color(rgba: BlackoutTokens.Color.raised) }
    static var warn: Color { Color(rgba: BlackoutTokens.Color.warn) }

    /// Dark glass the HUD sits on. Blur alone lets streets through the type.
    static func glass(opacity: Double = 0.72) -> some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(void.opacity(opacity))
        }
    }
}

extension Color {
    init(rgba: BlackoutTokens.RGBA) {
        self.init(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}

/// The product mark on the glass. Same compass as the App Icon and boot.
struct HUDMark: View {
    var points: Double = BlackoutTokens.Chrome.hudMarkPoints

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: CGFloat(points), height: CGFloat(points))
            .accessibilityHidden(true)
    }
}

/// The logo's center, as a selected-tab tick. Not a random underline.
struct HUDReticle: View {
    var lit: Bool

    var body: some View {
        let ink = lit ? Theme.accent : Color.clear
        let size = CGFloat(BlackoutTokens.Chrome.hudReticlePoints)
        return ZStack {
            Circle()
                .stroke(ink, lineWidth: 1)
            Rectangle()
                .fill(ink)
                .frame(width: size, height: 1)
            Rectangle()
                .fill(ink)
                .frame(width: 1, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Full-width 44pt dock cell. Equal split, no tail-ellipsis.
struct HUDDockStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let hit = BlackoutTokens.Chrome.mapChipHitPoints
        return configuration.label
            .font(.system(size: 12, weight: .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: hit, maxHeight: hit)
            .contentShape(Rectangle())
            .foregroundStyle(Theme.silver)
            .background(Theme.raised.opacity(configuration.isPressed ? 0.55 : 1))
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.silver.opacity(0.28), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// Glass page over the still-mounted map. COMMS / FIELD / EXPEDITION speak
/// this language so they are not a form dump next to a HUD.
struct HUDPage<Content: View>: View {
    let title: String
    var status: String = ""
    var warn: Bool = false
    var content: Content

    init(
        title: String,
        status: String = "",
        warn: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.status = status
        self.warn = warn
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                HUDMark()
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                Spacer(minLength: 8)
                if !status.isEmpty {
                    Text(status)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(warn ? Theme.warn : Theme.silver)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.glass(opacity: 0.78))
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.silver.opacity(0.22), lineWidth: 1)
            )
    }
}

struct HUDActionStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(filled ? Color.white : Theme.silver)
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            .contentShape(Rectangle())
            .background(filled ? Theme.accent : Theme.raised)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.silver.opacity(filled ? 0 : 0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
