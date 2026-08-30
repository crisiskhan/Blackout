import BlackoutCore
import BlackoutMesh
import DesignSystem
import SwiftUI

public struct MessagingRootView: View {
    let persistence: any PersistenceServing
    let crypto: any CryptoServing
    @Bindable var mesh: MeshFacade
    @Bindable var roster: PartyRoster

    @State private var draft = UserDefaults.standard.string(forKey: "com.crisiskhan.blackout.comms.draft") ?? ""
    @State private var rows: [DisplayMessage] = []
    @State private var error: String?

    public init(
        persistence: any PersistenceServing,
        crypto: any CryptoServing,
        mesh: MeshFacade,
        roster: PartyRoster
    ) {
        self.persistence = persistence
        self.crypto = crypto
        self.mesh = mesh
        self.roster = roster
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                ScreenHeader("Comms", subtitle: "Local radio. Ciphertext on disk.")
                Spacer()
                MeshPill(nearbyCount: roster.peerCount)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            List {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.body)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.bright)
                        Text("from \(row.from)")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.mid)
                        HStack {
                            Text(row.status.rawValue)
                                .font(BlackoutDS.captionFont())
                                .foregroundStyle(statusColor(row.status))
                            Spacer()
                            Text(row.createdAt.formatted(date: .omitted, time: .shortened))
                                .font(BlackoutDS.captionFont())
                                .foregroundStyle(BlackoutDS.Silver.steel)
                        }
                    }
                    .listRowBackground(BlackoutDS.Surface.raised)
                }
            }
            .scrollContentBackground(.hidden)
            if let error {
                StoreFailure(error)
                    .padding(.horizontal, 20)
            }
            VStack(spacing: 12) {
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
                HStack(spacing: 10) {
                    MetalButton("Send to self", height: BlackoutDS.Hit.md, action: sendToSelf)
                    GhostButton("Queue mesh", height: BlackoutDS.Hit.md, action: queueMesh)
                }
            }
            .padding(16)
            .padding(.bottom, 96)
        }
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .onChange(of: draft) { _, value in
            UserDefaults.standard.set(value, forKey: "com.crisiskhan.blackout.comms.draft")
        }
        .onChange(of: mesh.inboundSequence) { _, _ in
            reload()
        }
        .task { reload() }
    }

    private func statusColor(_ status: MessageStatus) -> Color {
        switch status {
        case .sealed: return BlackoutDS.Semantic.info
        case .queued: return BlackoutDS.Semantic.warn
        case .onMesh: return BlackoutDS.Semantic.ok
        }
    }

    private func sendToSelf() {
        commit(status: .sealed, recipient: crypto.localIdentity)
    }

    private func queueMesh() {
        let recipient = crypto.preferredRecipient
        let sealedToPeer = recipient != crypto.localIdentity
        let status: MessageStatus = (mesh.nearbyPeerCount > 0 && sealedToPeer) ? .onMesh : .queued
        commit(status: status, recipient: recipient)
    }

    private func commit(status: MessageStatus, recipient: BlackoutID) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let plaintext = text.data(using: .utf8) else { return }
        do {
            let sealed = try crypto.seal(plaintext, to: recipient)
            let record = MessageRecordDTO(
                ciphertext: sealed,
                status: status,
                senderID: crypto.localIdentity,
                recipientID: recipient
            )
            try persistence.saveMessage(record)
            if status != .sealed {
                mesh.send(
                    Envelope(
                        id: record.id,
                        kind: .message,
                        timestamp: record.createdAt,
                        ciphertext: sealed,
                        sender: record.senderID,
                        recipient: record.recipientID
                    )
                )
            }
            draft = ""
            UserDefaults.standard.removeObject(forKey: "com.crisiskhan.blackout.comms.draft")
            error = nil
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fromLabel(sender: BlackoutID) -> String {
        if sender == roster.localID || sender == crypto.localIdentity {
            return roster.identity.callsign
        }
        if let peer = roster.peers.first(where: { $0.id == sender }) {
            return peer.shortName
        }
        return String(sender.rawValue.uuidString.prefix(8))
    }

    private func reload() {
        do {
            let stored = try persistence.messages()
            rows = stored.map { record in
                let body: String
                if let data = try? crypto.open(record.ciphertext),
                   let text = String(data: data, encoding: .utf8) {
                    body = text
                } else {
                    body = "(unable to open)"
                }
                return DisplayMessage(
                    id: record.id,
                    body: body,
                    from: fromLabel(sender: record.senderID),
                    status: record.status,
                    createdAt: record.createdAt
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct DisplayMessage: Identifiable {
    var id: BlackoutID
    var body: String
    var from: String
    var status: MessageStatus
    var createdAt: Date
}
