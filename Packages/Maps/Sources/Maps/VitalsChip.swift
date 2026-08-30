import BlackoutCore
import DesignSystem
import SwiftUI

/// 56pt I'm-OK / I'm-not. Recedes with Map HUD. Not a second SOS disk.
struct VitalsChip: View {
    var band: PartyBand
    var pending: PartyVitalAction?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(band == .red ? PartyVitalsCopy.imNot : PartyVitalsCopy.imOK)
                    .font(BlackoutDS.captionFont())
                    .fontWeight(.semibold)
                if showsConfirm {
                    Text(PartyVitalsCopy.tapAgain)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 16)
            .frame(height: BlackoutDS.Hit.sm)
            .background(fill)
            .overlay(
                Capsule().stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(band == .red ? PartyVitalsCopy.imNot : PartyVitalsCopy.imOK)
        .accessibilityHint(showsConfirm ? PartyVitalsCopy.tapAgain : "Two-tap to change status")
    }

    private var showsConfirm: Bool {
        switch band {
        case .red: return pending == .imOK
        case .green, .yellow: return pending == .notOK
        }
    }

    private var fill: Color {
        switch band {
        case .red: return BlackoutDS.Red.core
        case .yellow: return BlackoutDS.Surface.raised.opacity(0.82)
        case .green: return BlackoutDS.Surface.raised.opacity(0.82)
        }
    }

    private var labelColor: Color {
        switch band {
        case .red: return BlackoutDS.Silver.metal
        case .yellow, .green: return BlackoutDS.Silver.bright
        }
    }
}
