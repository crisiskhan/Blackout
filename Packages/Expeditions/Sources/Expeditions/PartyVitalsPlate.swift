import BlackoutCore
import DesignSystem
import SwiftUI

/// Roster plate: callsign, party create/join/leave, then DRANK / ATE / I AM NOT OK.
/// I AM NOT OK shares Map chip state.
struct PartyVitalsPlate: View {
    @Bindable var roster: PartyRoster
    var fix: LocationFix?
    var onBroadcast: (Envelope) -> Void
    var onCommitCallsign: (String) -> Void
    var onCreateParty: () -> Void
    var onJoinParty: (String) -> Bool
    var onLeaveParty: () -> Void

    @State private var callsignDraft = ""
    @State private var joinDraft = ""
    @State private var joinFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identityBlock
            metalButton(
                title: PartyVitalsCopy.drank,
                action: .drank,
                pip: roster.selfVitals.drankLatched ? .ok : nil,
                warnLabel: false
            )
            metalButton(
                title: PartyVitalsCopy.ate,
                action: .ate,
                pip: roster.selfVitals.ateLatched ? .ok : nil,
                warnLabel: false
            )
            metalButton(
                title: PartyVitalsCopy.notOK,
                action: .notOK,
                pip: roster.isRed ? .red : nil,
                warnLabel: roster.isRed
            )
            memberList
        }
        .onAppear {
            callsignDraft = roster.identity.callsign
        }
        .onChange(of: roster.identity.callsign) { _, value in
            callsignDraft = value
        }
    }

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            selfRow
            Text(PartyIdentityCopy.callsign)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
            TextField(Callsign.defaultValue, text: $callsignDraft)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
                .padding(14)
                .frame(height: BlackoutDS.Hit.sm)
                .background(BlackoutDS.Surface.sunken)
                .onChange(of: callsignDraft) { _, value in
                    if value.count > Callsign.maxLength {
                        callsignDraft = String(value.prefix(Callsign.maxLength))
                    }
                }
                .onSubmit { commitCallsign() }
            MetalButton(PartyIdentityCopy.save, height: BlackoutDS.Hit.sm, action: commitCallsign)
            partyControls
        }
    }

    private var selfRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(bandColor(roster.selfVitals.band))
                .frame(width: BlackoutDS.Vitals.pip, height: BlackoutDS.Vitals.pip)
            Text(roster.selfVitals.shortName)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            Spacer()
            Text(roster.isRed ? PartyVitalsCopy.imNot : PartyVitalsCopy.imOK)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(roster.isRed ? BlackoutDS.Semantic.warn : BlackoutDS.Silver.dim)
        }
        .accessibilityLabel("Self \(roster.selfVitals.shortName)")
    }

    @ViewBuilder
    private var partyControls: some View {
        if let code = roster.identity.partyCode {
            Text("\(PartyIdentityCopy.partyCode) \(code)")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            if roster.isFrozen {
                Text("Party ended. Roster frozen.")
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
            }
            HStack(spacing: 10) {
                GhostButton(PartyIdentityCopy.leave, height: BlackoutDS.Hit.sm, action: onLeaveParty)
                GhostButton(PartyIdentityCopy.end, height: BlackoutDS.Hit.sm, action: onLeaveParty)
            }
        } else {
            if roster.isFrozen {
                Text("Party ended. Roster frozen.")
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
            }
            Text(PartyIdentityCopy.soloValid)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
            MetalButton(PartyIdentityCopy.create, height: BlackoutDS.Hit.sm, action: onCreateParty)
            TextField(PartyIdentityCopy.partyCode, text: $joinDraft)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .padding(14)
                .frame(height: BlackoutDS.Hit.sm)
                .background(BlackoutDS.Surface.sunken)
                .onChange(of: joinDraft) { _, value in
                    joinDraft = PartyCode.normalize(value)
                    joinFailed = false
                }
            GhostButton(PartyIdentityCopy.join, height: BlackoutDS.Hit.sm) {
                joinFailed = !onJoinParty(joinDraft)
                if !joinFailed {
                    joinDraft = ""
                }
            }
            if joinFailed {
                Text("Party code is 4–8 A–Z 0–9.")
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Semantic.warn)
            }
        }
    }

    @ViewBuilder
    private var memberList: some View {
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

    private func commitCallsign() {
        onCommitCallsign(callsignDraft)
        callsignDraft = roster.identity.callsign
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
