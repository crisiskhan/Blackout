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
                .holdScroll()
            }
        }
    }

    private var radios: [NearRadio] { hold.radios }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titleLine)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(countLine)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.fix)
                .lineLimit(1)
                .minimumScaleFactor(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var titleLine: String {
        if hold.last { return "LAST HEARD" }
        if radios.count == 1 { return radios[0].name }
        return "NEAR"
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
            if radios.isEmpty {
                row(key: "KIND", value: kindsLine)
            }
            if !hold.signal.isEmpty {
                row(key: "SIGNAL", value: hold.signal)
            }
            ForEach(Array(radios.enumerated()), id: \.element.id) { index, radio in
                if radios.count > 1 || titleLine != radio.name {
                    Text(radio.name)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                        .padding(.top, index == 0 ? 4 : 8)
                }
                radioRows(radio)
            }
            row(key: "COORDINATES", value: hold.placed ? coordinates : "NO PLACE")
            row(key: "BEARING", value: hold.placed ? bearing : "NO PLACE")
        }
    }

    @ViewBuilder
    private func radioRows(_ radio: NearRadio) -> some View {
        row(key: "NAME", value: radio.name.isEmpty ? "UNNAMED" : radio.name)
        row(key: "KIND", value: radio.kind)
        if !radio.rssi.isEmpty {
            row(key: "RSSI", value: radio.rssi)
        }
        if !radio.reach.isEmpty {
            row(key: "REACH", value: radio.reach)
        }
        row(key: "RADIO", value: radio.radio)
        if !radio.maker.isEmpty {
            row(key: "MAKER", value: radio.maker)
        }
        if !radio.link.isEmpty {
            row(key: "LINK", value: radio.link)
        }
        if !radio.tx.isEmpty {
            row(key: "TX", value: radio.tx)
        }
        if radio.hop {
            row(key: "CARRY", value: "HOP")
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
            Button(hold.placed ? "WALK" : "WALK — NO PLACE") { onWalk() }
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
