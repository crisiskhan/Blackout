import BlackoutCore
import UIKit
import VoicePTT

/// Shared live PTT entry for App Intents, Action Button shortcuts, and Camera Control.
@MainActor
enum PTTIntentBridge {
    static weak var hub: LivePTTHub?

    static func bind(hub: LivePTTHub) {
        self.hub = hub
    }

    static func toggle() -> Bool {
        hub?.toggleFromExternal() ?? false
    }

    static func begin() -> Bool {
        hub?.beginFromExternal() ?? false
    }

    static func end() {
        hub?.endFromExternal()
    }

    static var lastRefusal: String {
        hub?.lastRefusal ?? PTTCopy.noMeshPress
    }
}
