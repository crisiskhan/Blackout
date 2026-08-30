import BlackoutCore
import DesignSystem
import SwiftUI

/// Existing pack catalog. FL/TX/NY/NM Ready bundled. Extras later.
public struct FieldPackCatalogList: View {
    @Bindable var store: PackStore
    var nearbyCount: Int
    var onSendToPeer: ((String) -> Void)?

    public init(
        store: PackStore,
        nearbyCount: Int = 0,
        onSendToPeer: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.nearbyCount = nearbyCount
        self.onSendToPeer = onSendToPeer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(FieldPackCatalog.all) { pack in
                packRow(pack)
            }
        }
        .onAppear { store.refreshStates() }
    }

    private func packRow(_ pack: FieldPackDescriptor) -> some View {
        let state = store.states[pack.id] ?? (pack.isBundled ? .ready : nil)
        return HUDPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(pack.title)
                        .font(BlackoutDS.titleFont())
                    Spacer()
                    if let state {
                        Text(label(for: state))
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(color(for: state))
                    }
                }
                Text(pack.summary)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                if let message = store.messages[pack.id], !message.isEmpty {
                    Text(message)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.mid)
                }
                if let fraction = store.progress[pack.id] {
                    Text("\(Int(fraction * 100))%")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                }
                if !pack.isBundled, !store.isReady(pack.id) {
                    MetalButton(state == .downloading ? "Downloading" : "Download", height: BlackoutDS.Hit.sm) {
                        store.download(pack.id)
                    }
                    .disabled(state == .downloading)
                    .opacity(state == .downloading ? 0.6 : 1)
                }
                if FieldPackCatalog.isRelayable(pack.id), store.isReady(pack.id) {
                    if PackRelayPolicy.sendEnabled(nearbyPeerCount: nearbyCount) {
                        let sending = store.progress[pack.id] != nil
                        MetalButton(sending ? "Sending" : PackRelayPolicy.sendLabel, height: BlackoutDS.Hit.sm) {
                            onSendToPeer?(pack.id)
                        }
                        .disabled(sending)
                        .opacity(sending ? 0.6 : 1)
                    } else {
                        Text("Send pack waits for a nearby phone.")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.steel)
                    }
                }
            }
        }
    }

    private func label(for state: FieldPackRowState) -> String {
        switch state {
        case .noWifi: return "No wifi"
        case .downloading: return "Downloading"
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }

    private func color(for state: FieldPackRowState) -> Color {
        switch state {
        case .ready: return BlackoutDS.Semantic.ok
        case .downloading: return BlackoutDS.Semantic.info
        case .noWifi: return BlackoutDS.Semantic.warn
        case .failed: return BlackoutDS.Silver.steel
        }
    }
}
