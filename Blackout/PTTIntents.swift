import AppIntents
import BlackoutCore

/// Action Button cannot be claimed except by an App Shortcut the user assigns in Settings.
struct StartPTTIntent: AppIntent {
    static var title: LocalizedStringResource = "Start PTT"
    static var description = IntentDescription("Talk on the live mesh. Same as the Comms disk.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await MainActor.run { PTTIntentBridge.begin() }
        if ok {
            return .result(dialog: "LIVE")
        }
        let copy = await MainActor.run { PTTIntentBridge.lastRefusal }
        return .result(dialog: IntentDialog(stringLiteral: copy))
    }
}

struct StopPTTIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop PTT"
    static var description = IntentDescription("End live PTT. Same as releasing the Comms disk.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { PTTIntentBridge.end() }
        return .result(dialog: "Stopped")
    }
}

struct TogglePTTIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle PTT"
    static var description = IntentDescription("Start or stop live PTT. Same as the Comms disk.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await MainActor.run { PTTIntentBridge.toggle() }
        if ok {
            return .result(dialog: "PTT")
        }
        let copy = await MainActor.run { PTTIntentBridge.lastRefusal }
        return .result(dialog: IntentDialog(stringLiteral: copy))
    }
}

struct BlackoutPTTShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: TogglePTTIntent(),
                phrases: [
                    "Toggle PTT in \(.applicationName)",
                    "Talk in \(.applicationName)",
                ],
                shortTitle: "Toggle PTT",
                systemImageName: "mic.fill"
            ),
            AppShortcut(
                intent: StartPTTIntent(),
                phrases: [
                    "Start PTT in \(.applicationName)",
                ],
                shortTitle: "Start PTT",
                systemImageName: "mic.fill"
            ),
            AppShortcut(
                intent: StopPTTIntent(),
                phrases: [
                    "Stop PTT in \(.applicationName)",
                ],
                shortTitle: "Stop PTT",
                systemImageName: "mic.slash"
            ),
        ]
    }
}
