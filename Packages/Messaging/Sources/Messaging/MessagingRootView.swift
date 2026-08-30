import BlackoutCore
import BlackoutMesh
import DesignSystem
import SwiftUI
import UIKit

public struct MessagingRootView: View {
    let outbox: CommsOutbox
    @Bindable var mesh: MeshFacade
    @Bindable var roster: PartyRoster
    var locationFix: LocationFix?
    var onOpenExpedition: () -> Void
    var onNavigatePing: (FieldPingNav) -> Void
    var onPingReplied: (() -> Void)?
    @Binding var pendingDM: BlackoutID?

    @State private var threads: [ChatThreadSummary] = []
    @State private var opened: ChatThreadRef?
    @State private var error: String?

    public init(
        outbox: CommsOutbox,
        mesh: MeshFacade,
        roster: PartyRoster,
        locationFix: LocationFix?,
        onOpenExpedition: @escaping () -> Void,
        onNavigatePing: @escaping (FieldPingNav) -> Void,
        onPingReplied: (() -> Void)? = nil,
        pendingDM: Binding<BlackoutID?>
    ) {
        self.outbox = outbox
        self.mesh = mesh
        self.roster = roster
        self.locationFix = locationFix
        self.onOpenExpedition = onOpenExpedition
        self.onNavigatePing = onNavigatePing
        self.onPingReplied = onPingReplied
        self._pendingDM = pendingDM
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    ScreenHeader("Threads", subtitle: headerSubtitle)
                    Spacer()
                    MeshPill(nearbyCount: mesh.nearbyPeerCount)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                if case .unsupportedVersion = mesh.lastEvent {
                    StoreFailure(MeshInbound.versionUnknownCopy)
                        .padding(.horizontal, 20)
                }
                if let error {
                    StoreFailure(error)
                        .padding(.horizontal, 20)
                }
                if showMeshOffBanner {
                    Text(CommsCopy.meshOffBanner)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Semantic.warn)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if threads.isEmpty {
                    emptyState
                } else {
                    threadList
                }
            }
            .background(BlackoutDS.Surface.base.ignoresSafeArea())
            .navigationDestination(item: $opened) { thread in
                ChatDetailView(
                    outbox: outbox,
                    mesh: mesh,
                    roster: roster,
                    thread: thread,
                    title: threads.first(where: { $0.ref == thread })?.title ?? threadTitle(thread),
                    locationFix: locationFix,
                    composeEnabled: composeEnabled(for: thread),
                    onNavigatePing: onNavigatePing,
                    onPingReplied: onPingReplied
                )
            }
        }
        .task {
            reload()
            openPendingDM()
        }
        .onChange(of: mesh.inboundSequence) { _, _ in reload() }
        .onChange(of: mesh.nearbyPeerCount) { _, _ in reload() }
        .onChange(of: pendingDM) { _, _ in
            openPendingDM()
        }
    }

    private var headerSubtitle: String {
        if roster.identity.isSolo {
            return "Solo. Mesh is off."
        }
        return "Local radio. Ciphertext on disk."
    }

    private var showMeshOffBanner: Bool {
        MeshGate.allowsTraffic(partyCode: roster.identity.partyCode)
            && (!mesh.isRunning || mesh.nearbyPeerCount == 0)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text(CommsCopy.noThreads)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
            HStack(spacing: 10) {
                MetalButton(PartyIdentityCopy.create, height: BlackoutDS.Hit.sm, action: onOpenExpedition)
                MetalButton(PartyIdentityCopy.join, height: BlackoutDS.Hit.sm, action: onOpenExpedition)
            }
            Spacer()
        }
        .padding(20)
        .padding(.bottom, BlackoutDS.Comms.composeClearance)
    }

    private var threadList: some View {
        List {
            ForEach(threads) { row in
                Button {
                    opened = row.ref
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.title)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.bright)
                        Text(row.lastBody ?? "No messages")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.dim)
                            .lineLimit(2)
                    }
                }
                .listRowBackground(BlackoutDS.Surface.raised)
            }
            if roster.peers.isEmpty {
                Text(CommsCopy.noPeersInRange)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .padding(.bottom, BlackoutDS.Comms.composeClearance)
    }

    private func composeEnabled(for thread: ChatThreadRef) -> Bool {
        switch thread.kind {
        case .group:
            return MeshGate.allowsTraffic(partyCode: roster.identity.partyCode)
        case .dm:
            return !roster.peers.isEmpty || thread.peerID != nil
        }
    }

    private func threadTitle(_ thread: ChatThreadRef) -> String {
        switch thread.kind {
        case .group:
            return PartyThread.groupTitle(
                selfCallsign: roster.identity.callsign,
                peerCallsigns: roster.peers.map(\.callsign)
            )
        case .dm:
            if let peer = roster.peers.first(where: { $0.id == thread.peerID }) {
                return roster.label(for: peer).name
            }
            return Callsign.defaultValue
        }
    }

    private func openPendingDM() {
        guard let id = pendingDM else { return }
        opened = .dm(peerID: id)
        pendingDM = nil
    }

    private func reload() {
        do {
            threads = try outbox.threads(
                partyCode: roster.identity.partyCode,
                peers: roster.peers.map { ($0.id, $0.callsign) },
                selfCallsign: roster.identity.callsign
            )
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ChatDetailView: View {
    let outbox: CommsOutbox
    @Bindable var mesh: MeshFacade
    @Bindable var roster: PartyRoster
    var thread: ChatThreadRef
    var title: String
    var locationFix: LocationFix?
    var composeEnabled: Bool
    var onNavigatePing: (FieldPingNav) -> Void
    var onPingReplied: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rows: [DisplayMessage] = []
    @State private var draft: String = ""
    @State private var pinOn = false
    @State private var error: String?
    @State private var selectedPingID: BlackoutID?
    @State private var dictateHint: String?

    private var draftKey: String {
        "com.crisiskhan.blackout.comms.draft.\(thread.id.rawValue.uuidString)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if showMeshOffBanner {
                Text(CommsCopy.meshOffBanner)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Semantic.warn)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        threadRow(row)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            composeBar
        }
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            draft = UserDefaults.standard.string(forKey: draftKey) ?? ""
            reload()
        }
        .onChange(of: draft) { _, value in
            UserDefaults.standard.set(value, forKey: draftKey)
        }
        .onChange(of: mesh.inboundSequence) { _, _ in reload() }
    }

    private var showMeshOffBanner: Bool {
        !mesh.isRunning || mesh.nearbyPeerCount == 0
    }

    private var activeInboundPing: DisplayMessage? {
        if let selectedPingID, let row = rows.first(where: { $0.id == selectedPingID }),
           !row.isMine, row.ping != nil {
            return row
        }
        return rows.last(where: { !$0.isMine && $0.ping != nil })
    }

    private var showReplyRow: Bool {
        guard let latest = rows.last else { return false }
        if let selected = activeInboundPing, selected.id == latest.id { return true }
        return !latest.isMine && latest.ping != nil
    }

    @ViewBuilder
    private func threadRow(_ row: DisplayMessage) -> some View {
        if let ping = row.ping {
            VStack(alignment: .leading, spacing: 8) {
                FieldPingCard(
                    title: FieldPing.label(ping),
                    callsign: row.callsign,
                    createdAt: row.createdAt,
                    footnote: row.pinFootnote,
                    hue: FieldPing.hue(ping),
                    status: row.status,
                    onTap: { selectPing(row) },
                    onRetry: row.status == .failed ? { retry(row.id) } : nil
                )
                if !row.isMine, activeInboundPing?.id == row.id, rows.last?.id != row.id {
                    FieldReplyRow(
                        enabled: composeEnabled,
                        reduceMotion: reduceMotion,
                        onReply: sendReply
                    )
                }
            }
        } else if let reply = row.reply {
            FieldPingCard(
                title: FieldPing.label(reply),
                callsign: row.callsign,
                createdAt: row.createdAt,
                footnote: row.hasPin || row.noFix ? row.pinFootnote : FieldPing.label(reply),
                hue: FieldPing.hue(reply),
                status: row.status,
                onTap: {
                    if let nav = row.navigation {
                        onNavigatePing(nav)
                    }
                },
                onRetry: row.status == .failed ? { retry(row.id) } : nil
            )
        } else {
            MessageBubble(
                row: row,
                onRetry: row.status == .failed ? { retry(row.id) } : nil
            )
        }
    }

    private func selectPing(_ row: DisplayMessage) {
        if !row.isMine { selectedPingID = row.id }
        if let nav = row.navigation {
            onNavigatePing(nav)
        }
    }

    private var composeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error {
                StoreFailure(error)
            }
            if !composeEnabled {
                Text(CommsCopy.noPeersInRange)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
            }
            FieldPingGrid(
                enabled: composeEnabled,
                reduceMotion: reduceMotion,
                onPing: sendPing
            )
            if showReplyRow, activeInboundPing != nil {
                FieldReplyRow(
                    enabled: composeEnabled,
                    reduceMotion: reduceMotion,
                    onReply: sendReply
                )
            }
            if let dictateHint {
                Text(dictateHint)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Semantic.warn)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
                    .padding(14)
                    .frame(minHeight: BlackoutDS.Hit.sm, alignment: .topLeading)
                    .background(BlackoutDS.Surface.sunken)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
                    )
                    .disabled(!composeEnabled)
                    .opacity(composeEnabled ? 1 : BlackoutDS.Comms.dimmed)
                Button {
                    pinOn.toggle()
                } label: {
                    Image(systemName: pinOn ? "mappin.circle.fill" : "mappin.circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(pinOn ? BlackoutDS.Silver.metal : BlackoutDS.Silver.mid)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                    .disabled(!composeEnabled || locationFix?.hasCoordinate != true)
                ComposeDictationButton(
                    text: $draft,
                    enabled: true,
                    onDenied: {
                        dictateHint = ConvenienceCopy.dictationDenied
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                )
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(BlackoutDS.Surface.void)
                        .frame(width: BlackoutDS.Hit.sm, height: BlackoutDS.Hit.sm)
                        .background(BlackoutDS.Silver.metal)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!composeEnabled)
                .opacity(composeEnabled ? 1 : BlackoutDS.Comms.dimmed)
                .accessibilityLabel("Send")
            }
        }
        .padding(16)
        .padding(.bottom, BlackoutDS.Comms.composeClearance)
    }

    private func sendPing(_ ping: FieldPingID) {
        do {
            _ = try outbox.sendPing(ping, fix: locationFix, thread: thread)
            error = nil
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendReply(_ reply: FieldReplyID) {
        do {
            _ = try outbox.sendReply(reply, fix: locationFix, thread: thread)
            selectedPingID = nil
            error = nil
            onPingReplied?()
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send() {
        do {
            _ = try outbox.send(
                text: draft,
                pin: pinOn ? locationFix : nil,
                thread: thread
            )
            draft = ""
            UserDefaults.standard.removeObject(forKey: draftKey)
            pinOn = false
            error = nil
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func retry(_ id: BlackoutID) {
        do {
            _ = try outbox.retry(id)
            error = nil
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reload() {
        do {
            let stored = try outbox.messages(in: thread)
            rows = stored.map { record in
                let body = outbox.openBody(record)
                return DisplayMessage(
                    id: record.id,
                    body: body.text,
                    hasPin: body.hasPin,
                    noFix: body.noFix,
                    pinFootnote: body.pinFootnote(),
                    ping: body.fieldPing,
                    reply: body.fieldReply,
                    latitude: body.latitude,
                    longitude: body.longitude,
                    senderID: record.senderID,
                    callsign: callsign(for: record.senderID),
                    isMine: record.senderID == roster.localID || record.senderID == outboxIdentity,
                    status: record.status,
                    createdAt: record.createdAt
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var outboxIdentity: BlackoutID { roster.identity.deviceID }

    private func callsign(for id: BlackoutID) -> String {
        if id == roster.localID || id == roster.identity.deviceID {
            return roster.selfLabel.name
        }
        if let peer = roster.peers.first(where: { $0.id == id }) {
            return roster.label(for: peer).name
        }
        return Callsign.defaultValue
    }
}

private struct MessageBubble: View {
    var row: DisplayMessage
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            if row.isMine { Spacer(minLength: 56) }
            VStack(alignment: row.isMine ? .trailing : .leading, spacing: 6) {
                Text(row.body)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
                if row.hasPin {
                    Text("Location pin")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.dim)
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: BlackoutDS.Comms.lockShield))
                        .foregroundStyle(BlackoutDS.Silver.steel)
                    Text(row.status.rawValue)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(statusColor(row.status))
                    if let onRetry {
                        Button(CommsCopy.retry, action: onRetry)
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.metal)
                    }
                }
            }
            .padding(12)
            .background(row.isMine ? BlackoutDS.Red.wash : BlackoutDS.Surface.overlay)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: .infinity, alignment: row.isMine ? .trailing : .leading)
            if !row.isMine { Spacer(minLength: 24) }
        }
    }

    private func statusColor(_ status: MessageStatus) -> Color {
        switch status {
        case .sealed: return BlackoutDS.Semantic.info
        case .queued: return BlackoutDS.Semantic.warn
        case .onMesh: return BlackoutDS.Semantic.ok
        case .failed: return BlackoutDS.Red.hot
        }
    }
}

private struct DisplayMessage: Identifiable {
    var id: BlackoutID
    var body: String
    var hasPin: Bool
    var noFix: Bool
    var pinFootnote: String
    var ping: FieldPingID?
    var reply: FieldReplyID?
    var latitude: Double?
    var longitude: Double?
    var senderID: BlackoutID
    var callsign: String
    var isMine: Bool
    var status: MessageStatus
    var createdAt: Date

    var navigation: FieldPingNav? {
        guard let latitude, let longitude else { return nil }
        let title = ping.map(FieldPing.label) ?? reply.map(FieldPing.label) ?? body
        return FieldPingNav(latitude: latitude, longitude: longitude, label: "\(callsign) · \(title)")
    }
}
