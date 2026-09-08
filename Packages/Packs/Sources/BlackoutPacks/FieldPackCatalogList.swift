import BlackoutCore
import DesignSystem
import SwiftUI

/// Existing pack catalog. Ready only when the zip is on this device. Extras later.
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
            updateMapsBlock
            ForEach(FieldPackCatalog.all) { pack in
                packRow(pack)
            }
        }
        .onAppear { store.refreshStates() }
    }

    private var batchRunning: Bool {
        FieldPackCatalog.installablePacks.contains { store.states[$0.id] == .downloading }
    }

    private var updateEnabled: Bool {
        FieldPackUpdatePolicy.updateMapsEnabled(
            downloadsAllowed: store.downloadsAllowed,
            pathSatisfied: store.pathSatisfied,
            batchRunning: batchRunning
        )
    }

    private var updateMapsBlock: some View {
        HUDPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Maps and topography")
                    .font(BlackoutDS.titleFont())
                Text("One tap keeps every Field Pack current. Topography lives inside these USGS packs.")
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                if !store.downloadsAllowed {
                    Text(FieldPackUpdatePolicy.lastTwoPercentCopy)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                } else if !store.pathSatisfied {
                    Text(FieldPackUpdatePolicy.noPathCopy)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                }
                let cellular = FieldPackUpdatePolicy.needsCellularConfirm(
                    pathSatisfied: store.pathSatisfied,
                    onWiFi: store.onWiFi
                )
                let title = cellular
                    ? FieldPackUpdatePolicy.useCellularLabel
                    : FieldPackUpdatePolicy.updateMapsLabel
                MetalButton(batchRunning ? "Updating" : title, height: BlackoutDS.Hit.md) {
                    store.updateAllMaps(allowCellular: cellular || store.onWiFi)
                }
                .disabled(!updateEnabled)
                .opacity(updateEnabled ? 1 : 0.6)
            }
        }
    }

    private func packRow(_ pack: FieldPackDescriptor) -> some View {
        let state = store.states[pack.id]
        let cityExtra = FieldPackCatalog.remotePacks.contains(where: { $0.id == pack.id })
        return HUDPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(pack.title)
                        .font(BlackoutDS.titleFont())
                    Spacer()
                    Text(rowLabel(for: state))
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(color(for: state))
                }
                if let size = FieldPackUpdatePolicy.byteSizeLabel(pack.byteCount) {
                    Text(size)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                }
                if FieldPackHonesty.showsCatalogSummary(isReady: store.isReady(pack.id)) {
                    Text(pack.summary)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.dim)
                }
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
                if FieldPackUpdatePolicy.showsRowGet(
                    isInstalled: store.isInstalled(pack.id),
                    isCityExtra: cityExtra,
                    hasRemoteURL: pack.downloadURL != nil
                ) {
                    rowGet(pack: pack, state: state)
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

    @ViewBuilder
    private func rowGet(pack: FieldPackDescriptor, state: FieldPackRowState?) -> some View {
        if !store.pathSatisfied {
            if FieldPackCatalog.isRelayable(pack.id), nearbyCount >= 1 {
                Text(FieldPackUpdatePolicy.nearbyGetCopy)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.steel)
            }
        } else if FieldPackUpdatePolicy.needsCellularConfirm(
            pathSatisfied: store.pathSatisfied,
            onWiFi: store.onWiFi
        ) {
            MetalButton(
                state == .downloading ? "Downloading" : FieldPackUpdatePolicy.useCellularLabel,
                height: BlackoutDS.Hit.sm
            ) {
                store.download(pack.id, allowCellular: true)
            }
            .disabled(state == .downloading || !store.downloadsAllowed)
            .opacity(state == .downloading ? 0.6 : 1)
        } else {
            MetalButton(
                state == .downloading ? "Downloading" : FieldPackUpdatePolicy.getLabel,
                height: BlackoutDS.Hit.sm
            ) {
                store.download(pack.id)
            }
            .disabled(state == .downloading || !store.downloadsAllowed)
            .opacity(state == .downloading ? 0.6 : 1)
        }
    }

    private func rowLabel(for state: FieldPackRowState?) -> String {
        guard let state else { return "Available" }
        switch state {
        case .noWifi: return "No wifi"
        case .downloading: return "Downloading"
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }

    private func color(for state: FieldPackRowState?) -> Color {
        guard let state else { return BlackoutDS.Silver.mid }
        switch state {
        case .ready: return BlackoutDS.Semantic.ok
        case .downloading: return BlackoutDS.Semantic.info
        case .noWifi: return BlackoutDS.Semantic.warn
        case .failed: return BlackoutDS.Silver.steel
        }
    }
}
