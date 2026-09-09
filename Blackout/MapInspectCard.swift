import SwiftUI
import MapLibreMap
import Tokens

/// What a stationary press found, over the map rather than instead of it.
///
/// Half the glass at the very most, and the map lifts the pin clear of the top
/// edge before this appears, so the thing being described is still visible
/// while it is being described.
struct MapInspectCard: View {
    @Bindable var runtime: AppRuntime
    let finding: InspectFinding
    let maxHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.accent)
                .frame(height: 2)
            VStack(alignment: .leading, spacing: 10) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        row(label: "WHY", text: finding.why)
                        row(label: "DO", text: finding.doLine, labelInk: Theme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                actions
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: maxHeight, alignment: .top)
        .background(.ultraThinMaterial)
        .background(Theme.void.opacity(0.78))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(finding.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(finding.title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if let sure = finding.sure {
                    Text("SURE \(sure)%")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.accent)
                        .fixedSize()
                }
            }
            // The one thing a percent on a water card must never be read as.
            if finding.sure != nil {
                Text(WaterSure.disclaimer)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(white: 0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(label: String, text: String, labelInk: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(labelInk ?? Color(white: 0.55))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.silver)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(InspectField.label(for: finding.fieldCardID)) {
                runtime.openField(cardID: finding.fieldCardID)
            }
            .buttonStyle(InspectActionStyle(filled: true))
            Button("MARK") { runtime.markInspection() }
                .buttonStyle(InspectActionStyle(filled: false))
            Spacer(minLength: 0)
            Button("CLOSE") { runtime.closeInspect() }
                .buttonStyle(InspectActionStyle(filled: false))
        }
    }
}

private struct InspectActionStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(filled ? Color.white : Theme.silver)
            .padding(.horizontal, 14)
            .frame(minWidth: 64, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            .contentShape(Rectangle())
            .background(filled ? Theme.accent : Theme.raised)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
