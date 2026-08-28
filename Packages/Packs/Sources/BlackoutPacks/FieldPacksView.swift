import BlackoutCore
import DesignSystem
import SwiftUI

public struct FieldPacksView: View {
    @Bindable var store: PackStore
    var onSkip: () -> Void

    public init(store: PackStore, onSkip: @escaping () -> Void) {
        self.store = store
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                GhostButton("Skip", height: BlackoutDS.Hit.sm, action: onSkip)
                    .frame(width: 120)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(
                        "Field Packs",
                        subtitle: "Download El Paso, Las Cruces, or Albuquerque on Wi-Fi, then they work airplane. Texas and New Mexico statewide are not on Releases yet. Skip uses the bundled Denver sample. SOS stays available."
                    )
                    if !store.onWiFi {
                        Text(store.pathSatisfied
                             ? "Cellular. Prefers Wi-Fi. Download still only happens if you tap it here — never on boot."
                             : "No Wi-Fi. Airplane uses whatever packs are already on this device.")
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Semantic.warn)
                    }
                    ForEach(FieldPackCatalog.all) { pack in
                        packRow(pack)
                    }
                    GhostButton("Skip and go to Map", height: BlackoutDS.Hit.md, action: onSkip)
                }
                .padding(20)
                .padding(.bottom, 120)
            }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BlackoutDS.Surface.void.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { store.refreshStates() }
    }

    private func packRow(_ pack: FieldPackDescriptor) -> some View {
        let state = store.states[pack.id] ?? (
            pack.isBundled ? .ready : (pack.assetReady ? .available : .failed)
        )
        return HUDPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(pack.title)
                        .font(BlackoutDS.titleFont())
                    Spacer()
                    Text(label(for: state))
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(color(for: state))
                }
                Text(pack.summary)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                if let message = store.messages[pack.id], !message.isEmpty {
                    Text(message)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.mid)
                }
                if !pack.isBundled, state != .ready {
                    MetalButton(state == .downloading ? "Downloading" : "Download", height: BlackoutDS.Hit.sm) {
                        store.download(pack.id)
                    }
                    .disabled(state == .downloading)
                    .opacity(state == .downloading ? 0.6 : 1)
                }
            }
        }
    }

    private func label(for state: FieldPackRowState) -> String {
        switch state {
        case .noWifi: return "no wifi"
        case .downloading: return "downloading"
        case .available: return "available"
        case .ready: return "ready"
        case .failed: return "failed"
        case .skip: return "skip"
        }
    }

    private func color(for state: FieldPackRowState) -> Color {
        switch state {
        case .ready: return BlackoutDS.Semantic.ok
        case .available, .downloading: return BlackoutDS.Semantic.info
        case .noWifi: return BlackoutDS.Semantic.warn
        case .failed, .skip: return BlackoutDS.Silver.steel
        }
    }
}
