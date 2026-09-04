import ActivityKit
import SwiftUI
import WidgetKit

struct SOSAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var kind: String
        var detail: String
    }
    var title: String
}

struct BlackoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SOSAttributes.self) { context in
            VStack {
                Text(context.attributes.title)
                Text(context.state.detail)
            }
            .preferredColorScheme(.dark)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.state.kind) }
                DynamicIslandExpandedRegion(.trailing) { Text("SOS") }
            } compactLeading: { Text("BO") } compactTrailing: { Text(context.state.kind) } minimal: { Text("!") }
        }
    }
}

@main
struct BlackoutWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BlackoutLiveActivity()
        // TestFlight slice: SOSControl (AppIntents) omitted — no Metadata.appintents.
    }
}
