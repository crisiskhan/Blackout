import BlackoutCore
import DesignSystem
import SwiftUI

/// Overlay-only PTT. Not a Comms segment. Voicemail / clip list is not the product.
public struct VoicePTTRootView: View {
    @Bindable var hub: LivePTTHub
    var nearbyPeerCount: Int
    var partyCode: String?
    var meshRunning: Bool
    var onOpenSettings: () -> Void

    public init(
        hub: LivePTTHub,
        nearbyPeerCount: Int,
        partyCode: String?,
        meshRunning: Bool,
        onOpenSettings: @escaping () -> Void
    ) {
        self.hub = hub
        self.nearbyPeerCount = nearbyPeerCount
        self.partyCode = partyCode
        self.meshRunning = meshRunning
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        let decision = hub.decision(
            nearbyPeerCount: nearbyPeerCount,
            partyCode: partyCode,
            meshRunning: meshRunning
        )
        PTTHoldButton(
            decision: decision,
            isTransmitting: hub.isTransmitting,
            refusal: hub.lastRefusal,
            onPress: { hub.pressBegan(decision: decision) },
            onRelease: { hub.pressEnded() },
            onDeniedTap: {
                hub.noteRefusal(decision.pressMessage)
                if decision.showOpenSettings {
                    onOpenSettings()
                }
            }
        )
        .task {
            await hub.refreshMicrophone()
        }
    }
}
