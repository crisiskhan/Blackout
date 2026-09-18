import SwiftUI
import MeshDTN
import Tokens

/// Heard radios on the field. Not a party body. WALK is the street path.
/// There is no phone number here and never will be.
struct NearHoldCard: View {
    let hold: NearHold
    let bearing: String
    let coordinates: String
    let onWalk: () -> Void
    let onClose: () -> Void

    var body: some View {
        HoldGlassShell(onClose: onClose) {
            VStack(alignment: .leading, spacing: 10) {
                headline
                Rectangle()
                    .fill(Theme.silver.opacity(0.22))
                    .frame(height: 1)
                actions
                ScrollView {
                    rows
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NEAR")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(1)
            Text(countLine)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.fix)
                .lineLimit(1)
                .minimumScaleFactor(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var countLine: String {
        hold.count == 1 ? "1 DEVICE" : "\(hold.count) DEVICES"
    }

    private var kindsLine: String {
        let words = hold.kinds.map(Self.kindWord).filter { !$0.isEmpty }
        return words.isEmpty ? "HEARD" : words.joined(separator: " · ")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(key: "COUNT", value: countLine)
            row(key: "KIND", value: kindsLine)
            row(key: "COORDINATES", value: coordinates)
            row(key: "BEARING", value: bearing)
        }
    }

    private func row(key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.75))
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("WALK") { onWalk() }
                .buttonStyle(HoldActionStyle(filled: false, expand: true))
        }
    }

    private static func kindWord(_ raw: String) -> String {
        switch raw {
        case "apple":
            return "IPHONE"
        case "samsung":
            return "SAMSUNG"
        case "hop":
            return "HOP"
        case "device":
            return "DEVICE"
        default:
            return raw.uppercased()
        }
    }
}
