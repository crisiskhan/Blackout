import BlackoutCore
import SwiftUI

/// Recenter / Layers / Packs. 56h painted chip, 22pt glyph. 64 slop is invisible inset, not the face.
public struct MapHUDChip: View {
    private let title: String
    private let systemName: String
    private let action: () -> Void

    public init(_ title: String, systemName: String, action: @escaping () -> Void) {
        self.title = title
        self.systemName = systemName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: CGFloat(MapChromeLock.chipGlyphPoint), weight: .semibold))
                Text(title)
                    .font(BlackoutDS.captionFont())
                    .fontWeight(.semibold)
            }
            .foregroundStyle(BlackoutDS.Silver.metal)
            .padding(.horizontal, 10)
            .frame(height: CGFloat(MapChromeLock.chipPaintedHeight))
            .background(BlackoutDS.Surface.raised.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(CGFloat(MapChromeLock.chipHitSlopInset))
        .contentShape(Rectangle())
        .padding(-CGFloat(MapChromeLock.chipHitSlopInset))
        .accessibilityLabel(title)
    }
}
