import BlackoutCore
import DesignSystem
import SwiftUI

/// DS §10.4 segmented metal chip. 56h. Metal plate, not a disk. Does not arm SOS.
public struct VitalsChip: View {
    var isOKLatched: Bool
    var isNotLatched: Bool
    var pending: PartyVitalAction?
    var onOK: () -> Void
    var onNot: () -> Void

    public init(
        isOKLatched: Bool,
        isNotLatched: Bool,
        pending: PartyVitalAction?,
        onOK: @escaping () -> Void,
        onNot: @escaping () -> Void
    ) {
        self.isOKLatched = isOKLatched
        self.isNotLatched = isNotLatched
        self.pending = pending
        self.onOK = onOK
        self.onNot = onNot
    }

    public var body: some View {
        HStack(spacing: 0) {
            segment(
                title: PartyVitalsCopy.imOK,
                pip: isOKLatched ? .ok : nil,
                warnLabel: false,
                pending: pending == .imOK,
                action: onOK
            )
            Rectangle()
                .fill(BlackoutDS.Silver.edge)
                .frame(width: 0.5, height: 28)
            segment(
                title: PartyVitalsCopy.imNot,
                pip: isNotLatched ? .red : nil,
                warnLabel: isNotLatched,
                pending: pending == .notOK,
                action: onNot
            )
        }
        .frame(height: BlackoutDS.Vitals.chip)
        .background(BlackoutDS.Btn.metal)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private enum Pip {
        case ok
        case red
    }

    private func segment(
        title: String,
        pip: Pip?,
        warnLabel: Bool,
        pending: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let pip {
                    Circle()
                        .fill(pipColor(pip))
                        .frame(width: BlackoutDS.Vitals.pip, height: BlackoutDS.Vitals.pip)
                }
                VStack(spacing: 2) {
                    Text(title)
                        .font(BlackoutDS.captionFont())
                        .fontWeight(.semibold)
                    if pending {
                        Text(PartyVitalsCopy.tapAgain)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
            }
            .foregroundStyle(warnLabel ? BlackoutDS.Semantic.warn : BlackoutDS.Surface.void)
            .padding(.horizontal, 12)
            .frame(height: BlackoutDS.Vitals.chip)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(pip != nil ? .isSelected : [])
        .accessibilityHint(pending ? PartyVitalsCopy.tapAgain : "Two-tap to change status")
    }

    private func pipColor(_ pip: Pip) -> Color {
        switch pip {
        case .ok: return BlackoutDS.Semantic.ok
        case .red: return BlackoutDS.Red.core
        }
    }
}
