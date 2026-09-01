import ActivityKit
import BlackoutCore
import SwiftUI
import WidgetKit

@main
struct BlackoutWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BlackoutLiveActivityWidget()
    }
}

struct BlackoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BlackoutLiveAttributes.self) { context in
            lockBanner(context.state)
                .widgetURL(BlackoutLiveLink.url(openMap: context.state.openMap))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.callsign)
                        .font(.headline)
                        .foregroundStyle(Color(red: 1, green: 43 / 255, blue: 43 / 255))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.peerCount)")
                        .font(.headline)
                        .foregroundStyle(Color(red: 244 / 255, green: 247 / 255, blue: 250 / 255))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.lastPingLabel)
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 180 / 255, green: 188 / 255, blue: 198 / 255))
                }
            } compactLeading: {
                Text(context.state.callsign)
                    .foregroundStyle(Color(red: 1, green: 43 / 255, blue: 43 / 255))
            } compactTrailing: {
                Text("\(context.state.peerCount)")
                    .foregroundStyle(Color(red: 244 / 255, green: 247 / 255, blue: 250 / 255))
            } minimal: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(Color(red: 1, green: 43 / 255, blue: 43 / 255))
            }
            .widgetURL(BlackoutLiveLink.url(openMap: context.state.openMap))
        }
    }

    private func lockBanner(_ state: BlackoutLiveAttributes.ContentState) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BLACKOUT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 122 / 255, green: 132 / 255, blue: 144 / 255))
                Text(state.callsign)
                    .font(.headline)
                    .foregroundStyle(Color(red: 244 / 255, green: 247 / 255, blue: 250 / 255))
                Text(state.lastPingLabel)
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 1, green: 43 / 255, blue: 43 / 255))
            }
            Spacer(minLength: 8)
            Text("\(state.peerCount) nearby")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(red: 180 / 255, green: 188 / 255, blue: 198 / 255))
        }
        .padding(16)
        .activityBackgroundTint(Color(red: 7 / 255, green: 8 / 255, blue: 10 / 255))
        .activitySystemActionForegroundColor(Color(red: 244 / 255, green: 247 / 255, blue: 250 / 255))
        .preferredColorScheme(.dark)
    }
}
