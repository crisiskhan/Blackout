import BlackoutCore
import BlackoutMesh
import DesignSystem
import SwiftUI

public struct MessagingRootView: View {
    let persistence: any PersistenceServing
    let crypto: any CryptoServing
    @Bindable var mesh: MeshFacade

    @State private var draft = ""
    @State private var rows: [DisplayMessage] = []
    @State private var error: String?

    public init(persistence: any PersistenceServing, crypto: any CryptoServing, mesh: MeshFacade) {
        self.persistence = persistence
        self.crypto = crypto
        self.mesh = mesh
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                ScreenHeader("Comms", subtitle: "Seal to self. Ciphertext only on disk.")
                Spacer()
                MeshPill(nearbyCount: mesh.nearbyPeerCount)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            List {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.body)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.bright)
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
                Text(error)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Semantic.warn)
                    .padding(.horizontal, 20)
            }
            VStack(spacing: 12) {
                TextField("Message to self", text: $draft, axis: .vertical)
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
        commit(status: .sealed)
    }

    private func queueMesh() {
        commit(status: mesh.nearbyPeerCount > 0 ? .onMesh : .queued)
    }

    private func commit(status: MessageStatus) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let plaintext = text.data(using: .utf8) else { return }
        do {
            let sealed = try crypto.seal(plaintext, to: crypto.localIdentity)
            let record = MessageRecordDTO(
                ciphertext: sealed,
                status: status,
                senderID: crypto.localIdentity,
                recipientID: crypto.localIdentity
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
            error = nil
            reload()
        } catch {
            self.error = "Seal failed."
        }
    }

    private func reload() {
        let stored = (try? persistence.messages()) ?? []
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
                status: record.status,
                createdAt: record.createdAt
            )
        }
    }
}

private struct DisplayMessage: Identifiable {
    var id: BlackoutID
    var body: String
    var status: MessageStatus
    var createdAt: Date
}
