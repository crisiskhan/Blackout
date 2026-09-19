import SwiftUI
import Tokens

/// Glass record for a packed door. WALK draws the street path. MARK drops
/// the pin. There is no phone number here and never will be.
struct AddressHoldCard: View {
    let address: HeldAddress
    let bearing: String
    let coordinates: String
    let onWalk: () -> Void
    let onMark: () -> Void
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

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(address.name)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("ADDRESS")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.silver)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(key: "CITY", value: cityLine)
            row(key: "POST", value: postLine)
            row(key: "COORDINATES", value: coordinates)
            row(key: "SURE", value: "\(address.sure)%", note: address.why)
            row(key: "WHAT", value: whatLine)
            row(key: "BEARING", value: bearing)
        }
    }

    private var cityLine: String {
        let city = address.city.trimmingCharacters(in: .whitespacesAndNewlines)
        return city.isEmpty ? "—" : city
    }

    private var postLine: String {
        let post = address.post.trimmingCharacters(in: .whitespacesAndNewlines)
        return post.isEmpty ? "—" : post
    }

    private var whatLine: String {
        let what = address.what.trimmingCharacters(in: .whitespacesAndNewlines)
        return what.isEmpty ? "door on the street" : what
    }

    private func row(key: String, value: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.75))
                .frame(width: 88, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.silver)
                        .lineLimit(4)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("WALK") { onWalk() }
                .buttonStyle(HoldActionStyle(filled: false, expand: true))
            Button("MARK") { onMark() }
                .buttonStyle(HoldActionStyle(filled: address.marked, expand: true))
        }
    }
}
