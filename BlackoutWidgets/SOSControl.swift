import AppIntents
import SwiftUI
import WidgetKit

struct OfferSOSIntent: AppIntent {
    static var title: LocalizedStringResource = "CALL SOS"
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct IAMOKIntent: AppIntent {
    static var title: LocalizedStringResource = "I AM OK"
    func perform() async throws -> some IntentResult { .result() }
}

struct SOSControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.crisiskhan.blackout.sos") {
            ControlWidgetButton(action: OfferSOSIntent()) {
                Label("CALL SOS", systemImage: "sos")
            }
        }
    }
}
