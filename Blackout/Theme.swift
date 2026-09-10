import SwiftUI
import Tokens

enum Theme {
    static var void: Color { Color(rgba: BlackoutTokens.Color.void) }
    static var accent: Color { Color(rgba: BlackoutTokens.Color.accent) }
    static var silver: Color { Color(rgba: BlackoutTokens.Color.silver) }
    static var raised: Color { Color(rgba: BlackoutTokens.Color.raised) }

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

/// Overlay chip that keeps its whole word. Used for INST and LOCK on the canvas.
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
