import BlackoutCore
import BlackoutLocation
import BlackoutMesh
import DesignSystem
import Maps
import Messaging
import SwiftUI
import UIKit
import VoicePTT

struct CommsRootView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case threads = "Threads"
        case radar = "Radar"
        case roster = "Roster"
        var id: String { rawValue }
    }

    let outbox: CommsOutbox
    var mesh: MeshFacade
    @Bindable var roster: PartyRoster
    @Bindable var location: LocationService
    @Bindable var ptt: LivePTTHub
    var onOpenExpedition: () -> Void
    var onNavigatePing: (FieldPingNav) -> Void
    @Binding var pendingDM: BlackoutID?

    @State private var segment: Segment = .threads
    @State private var radarPeer: RadarBlip?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Picker("Comms", selection: $segment) {
                    ForEach(Segment.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                switch segment {
                case .threads:
                    MessagingRootView(
                        outbox: outbox,
                        mesh: mesh,
                        roster: roster,
                        locationFix: location.navigationFix ?? location.lastKnown,
                        onOpenExpedition: onOpenExpedition,
                        onNavigatePing: onNavigatePing,
                        pendingDM: $pendingDM
                    )
                case .radar:
                    commsRadar
                case .roster:
                    CommsRosterView(
                        roster: roster,
                        meshRunning: mesh.isRunning,
                        onMessage: { id in
                            pendingDM = id
                            segment = .threads
                        }
                    )
                }
            }
            pttOverlay
        }
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .onChange(of: pendingDM) { _, id in
            if id != nil { segment = .threads }
        }
        .sheet(item: $radarPeer) { blip in
            RadarPeerSheet(
                blip: blip,
                onMessage: {
                    radarPeer = nil
                    pendingDM = blip.id
                    segment = .threads
                },
                onNavigate: {
                    radarPeer = nil
                }
            )
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
    }

    private var commsRadar: some View {
        let blips = roster.radarBlips(selfFix: location.navigationFix ?? location.lastKnown)
        return VStack(alignment: .leading, spacing: 12) {
            ScreenHeader("Radar", subtitle: "Party members only. Stranger Radar stays off.")
                .padding(.horizontal, 20)
                .padding(.top, 12)
            RadarHUDView(
                headingUp: UserDefaults.standard.bool(forKey: BlackoutKeys.radarHeadingUp),
                headingDegrees: location.headingDegrees,
                peers: blips,
                sweepAudio: UserDefaults.standard.bool(forKey: BlackoutKeys.radarSweepAudio),
                onSelectPeer: { radarPeer = $0 },
                onSelectSelf: {}
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, BlackoutDS.Comms.composeClearance)
        }
    }

    private var pttOverlay: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                VoicePTTRootView(
                    hub: ptt,
                    nearbyPeerCount: mesh.nearbyPeerCount,
                    partyCode: roster.identity.partyCode,
                    meshRunning: mesh.isRunning,
                    onOpenSettings: openSettings
                )
                .onChange(of: mesh.nearbyPeerCount) { _, _ in
                    if !ptt.decision(
                        nearbyPeerCount: mesh.nearbyPeerCount,
                        partyCode: roster.identity.partyCode,
                        meshRunning: mesh.isRunning
                    ).allowsTransmit {
                        ptt.noteRefusal(PTTCopy.noMeshPress)
                    }
                }
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.bottom, pttBottomPadding)
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(true)
    }

    private var pttBottomPadding: CGFloat {
        let hasTabBar = sizeClass != .regular
        return BlackoutDS.Vitals.sosGap
            + (hasTabBar ? BlackoutDS.Vitals.tabBar : 0)
            + BlackoutDS.Vitals.homeIndicator
    }

    private func openSettings() {
        ptt.noteRefusal(PTTCopy.micDenied)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct CommsRosterView: View {
    @Bindable var roster: PartyRoster
    var meshRunning: Bool
    var onMessage: (BlackoutID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenHeader("Roster", subtitle: roster.identity.partyCode ?? PartyIdentityCopy.noParty)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            if roster.peers.isEmpty {
                Text(meshRunning ? CommsCopy.rosterEmpty : CommsCopy.noPeersInRange)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                    .padding(.horizontal, 20)
                Spacer()
            } else {
                List {
                    ForEach(roster.peers) { peer in
                        Button {
                            onMessage(peer.id)
                        } label: {
                            rosterRow(peer)
                        }
                        .listRowBackground(BlackoutDS.Surface.raised)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.bottom, BlackoutDS.Comms.composeClearance)
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
    }

    private func rosterRow(_ peer: PartyMemberStatus) -> some View {
        let shown = roster.label(for: peer)
        let stale = PartyThread.isStale(lastHeard: peer.updatedAt)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(shown.name)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(stale ? BlackoutDS.Silver.dim : BlackoutDS.Silver.bright)
                Text(peer.updatedAt.formatted(.relative(presentation: .named)))
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                if let footnote = shown.footnote {
                    Text(footnote)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.dim)
                }
                if stale {
                    Text(CommsCopy.stale)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                }
            }
            Spacer()
        }
        .frame(minHeight: BlackoutDS.Comms.rosterRow)
        .opacity(stale ? 0.72 : 1)
    }
}
