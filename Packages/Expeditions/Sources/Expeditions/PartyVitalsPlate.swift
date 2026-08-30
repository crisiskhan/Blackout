import BlackoutCore
import DesignSystem
import SwiftUI

/// DRANK / ATE / I AM NOT OK — each Btn.metal 56. I AM NOT OK shares Map chip state.
struct PartyVitalsPlate: View {
    @Bindable var roster: PartyRoster
    var fix: LocationFix?
    var onBroadcast: (Envelope) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            metalButton(
                title: PartyVitalsCopy.drank,
                action: .drank,
                pip: roster.selfStatus.drankLatched ? .ok : nil,
                warnLabel: false
            )
            metalButton(
                title: PartyVitalsCopy.ate,
                action: .ate,
                pip: roster.selfStatus.ateLatched ? .ok : nil,
                warnLabel: false
            )
            metalButton(
                title: PartyVitalsCopy.notOK,
                action: .notOK,
                pip: roster.isRed ? .red : nil,
                warnLabel: roster.isRed
            )
            if roster.peers.isEmpty {
                Text(ExpeditionPauseCopy.rosterEmpty)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
            } else {
                ForEach(roster.peers) { peer in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(bandColor(peer.band))
                            .frame(width: BlackoutDS.Vitals.pip, height: BlackoutDS.Vitals.pip)
                        Text(peer.shortName)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.bright)
                        Spacer()
                        Text(peer.band == .red ? PartyVitalsCopy.imNot : PartyVitalsCopy.imOK)
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(peer.band == .red ? BlackoutDS.Semantic.warn : BlackoutDS.Silver.dim)
                    }
                }
            }
        }
    }

    private enum Pip {
        case ok
        case red
    }

    private func metalButton(
        title: String,
        action: PartyVitalAction,
        pip: Pip?,
        warnLabel: Bool
    ) -> some View {
        Button {
            commit(action)
        } label: {
            HStack(spacing: 8) {
                if let pip {
                    Circle()
                        .fill(pipColor(pip))
                        .frame(width: BlackoutDS.Vitals.pip, height: BlackoutDS.Vitals.pip)
                }
                VStack(spacing: 2) {
                    Text(title)
                        .font(BlackoutDS.bodyFont())
                        .fontWeight(.semibold)
                    if roster.pending == action {
                        Text(PartyVitalsCopy.tapAgain)
                            .font(BlackoutDS.captionFont())
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(warnLabel ? BlackoutDS.Semantic.warn : BlackoutDS.Surface.void)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: BlackoutDS.Vitals.chip)
            .background(BlackoutDS.Btn.metal)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(pip != nil ? .isSelected : [])
    }

    private func commit(_ action: PartyVitalAction) {
        if let envelope = roster.tap(action, fix: fix) {
            onBroadcast(envelope)
        }
    }

    private func pipColor(_ pip: Pip) -> Color {
        switch pip {
        case .ok: return BlackoutDS.Semantic.ok
        case .red: return BlackoutDS.Red.core
        }
    }

    private func bandColor(_ band: PartyBand) -> Color {
        switch band {
        case .green: return BlackoutDS.Semantic.ok
        case .yellow: return BlackoutDS.Semantic.warn
        case .red: return BlackoutDS.Red.core
        }
    }
}
