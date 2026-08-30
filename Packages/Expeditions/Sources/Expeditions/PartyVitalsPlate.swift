import BlackoutCore
import DesignSystem
import SwiftUI

/// Two-tap DRANK / ATE / I'M NOT OK on the Pause roster plate. Manual only.
struct PartyVitalsPlate: View {
    @Bindable var roster: PartyRoster
    var fix: LocationFix?
    var onBroadcast: (Envelope) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(bandColor(roster.selfStatus.band))
                    .frame(width: 10, height: 10)
                Text(roster.isRed ? PartyVitalsCopy.imNot : PartyVitalsCopy.imOK)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(roster.isRed ? BlackoutDS.Red.hot : BlackoutDS.Silver.bright)
            }
            HStack(spacing: 8) {
                vitalButton(.drank, title: PartyVitalsCopy.drank)
                vitalButton(.ate, title: PartyVitalsCopy.ate)
            }
            notOKButton
            if roster.peers.isEmpty {
                Text(ExpeditionPauseCopy.rosterEmpty)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
            } else {
                ForEach(roster.peers) { peer in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(bandColor(peer.band))
                            .frame(width: 10, height: 10)
                        Text(peer.shortName)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.bright)
                        Spacer()
                        Text(peer.band == .red ? PartyVitalsCopy.imNot : PartyVitalsCopy.imOK)
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(peer.band == .red ? BlackoutDS.Red.hot : BlackoutDS.Silver.dim)
                    }
                }
            }
        }
    }

    private var notOKButton: some View {
        Button {
            commit(.notOK)
        } label: {
            VStack(spacing: 2) {
                Text(PartyVitalsCopy.notOK)
                    .font(BlackoutDS.bodyFont())
                    .fontWeight(.semibold)
                if roster.pending == .notOK {
                    Text(PartyVitalsCopy.tapAgain)
                        .font(BlackoutDS.captionFont())
                }
            }
            .foregroundStyle(BlackoutDS.Silver.metal)
            .frame(maxWidth: .infinity)
            .frame(height: BlackoutDS.Hit.sm)
            .background(BlackoutDS.Red.core)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PartyVitalsCopy.notOK)
        .accessibilityHint(roster.pending == .notOK ? PartyVitalsCopy.tapAgain : "Two-tap to mark not OK")
    }

    private func vitalButton(_ action: PartyVitalAction, title: String) -> some View {
        Button {
            commit(action)
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(BlackoutDS.bodyFont())
                    .fontWeight(.semibold)
                if roster.pending == action {
                    Text(PartyVitalsCopy.tapAgain)
                        .font(BlackoutDS.captionFont())
                }
            }
            .foregroundStyle(BlackoutDS.Surface.void)
            .frame(maxWidth: .infinity)
            .frame(height: BlackoutDS.Hit.sm)
            .background(BlackoutDS.Silver.metal)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func commit(_ action: PartyVitalAction) {
        if let envelope = roster.tap(action, fix: fix) {
            onBroadcast(envelope)
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
