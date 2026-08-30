import BlackoutCore
import DesignSystem
import SwiftUI

public struct FieldPacksView: View {
    @Bindable var store: PackStore
    var nearbyCount: Int
    var onSendToPeer: ((String) -> Void)?
    var onSkip: () -> Void

    public init(
        store: PackStore,
        nearbyCount: Int = 0,
        onSendToPeer: ((String) -> Void)? = nil,
        onSkip: @escaping () -> Void
    ) {
        self.store = store
        self.nearbyCount = nearbyCount
        self.onSendToPeer = onSendToPeer
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
                        subtitle: "Florida, Texas, New York, and New Mexico are already on this phone — Ready, no download. Optional extras: El Paso, Las Cruces, or Albuquerque on Wi-Fi or one nearby phone. Denver is the fallback outside those states. SOS stays available."
                    )
                    if !store.onWiFi {
                        Text(store.pathSatisfied
                             ? "Cellular. Prefers Wi-Fi. Download still only happens if you tap it here — never on boot."
                             : "No Wi-Fi. Airplane uses whatever packs are already on this device.")
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Semantic.warn)
                    }
                    FieldPackCatalogList(
                        store: store,
                        nearbyCount: nearbyCount,
                        onSendToPeer: onSendToPeer
                    )
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
}
