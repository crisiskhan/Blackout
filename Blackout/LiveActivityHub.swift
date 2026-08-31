#if canImport(ActivityKit)
import ActivityKit
#endif
import BlackoutCore
import Foundation

/// Starts / ends the lock-screen Live Activity. Never a second SOS fire.
@MainActor
enum LiveActivityHub {
    static func sync(
        partyCode: String?,
        inbound: LatestInboundPing?,
        peerCount: Int,
        callsign: String,
        newBinaryLaunch: Bool = false
    ) {
#if canImport(ActivityKit)
        guard LiveActivityPolicy.shouldTouchActivityKit(newBinaryLaunch: newBinaryLaunch) else { return }
        let open = inbound.flatMap { $0.isOpen() ? $0 : nil }
        let should = LiveActivityPolicy.shouldBeActive(partyCode: partyCode, inboundPing: open)
        let state = BlackoutLiveAttributes.ContentState(
            callsign: Callsign.commit(open?.callsign ?? callsign),
            lastPingLabel: open?.label ?? "No ping",
            peerCount: peerCount,
            openMap: open != nil
        )
        if should {
            startOrUpdate(state: state)
        } else {
            end(newBinaryLaunch: newBinaryLaunch)
        }
#endif
    }

    static func end(newBinaryLaunch: Bool = false) {
#if canImport(ActivityKit)
        guard LiveActivityPolicy.shouldTouchActivityKit(newBinaryLaunch: newBinaryLaunch) else { return }
        for activity in Activity<BlackoutLiveAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
#endif
    }

#if canImport(ActivityKit)
    private static func startOrUpdate(state: BlackoutLiveAttributes.ContentState) {
        if let current = Activity<BlackoutLiveAttributes>.activities.first {
            Task { await current.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        do {
            _ = try Activity.request(
                attributes: BlackoutLiveAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            return
        }
    }
#endif
}
