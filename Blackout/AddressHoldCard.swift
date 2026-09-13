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

    @State private var drag: CGFloat = 0

    private static let smallestUsableCard: CGFloat = 180

    private var corner: CGFloat { CGFloat(BlackoutTokens.Chrome.holdCardCornerPoints) }

    var body: some View {
        GeometryReader { canvas in
            let cap = max(
                Self.smallestUsableCard,
                canvas.size.height * CGFloat(BlackoutTokens.Chrome.holdCardMaxHeightFraction)
            )
            ZStack(alignment: .bottom) {
                scrim
                card(cappedAt: cap)
                    .offset(y: drag)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { drag = max(0, $0.translation.height) }
                    .onEnded { value in
                        if value.translation.height > CGFloat(BlackoutTokens.Chrome.holdCardDismissDragPoints) {
                            onClose()
                        }
                        withAnimation(Theme.Motion.heavy) { drag = 0 }
                    }
            )
        }
        .transition(.opacity)
    }

    private var scrim: some View {
        LinearGradient(
            colors: [
                Theme.void.opacity(BlackoutTokens.Chrome.holdCardScrimTopOpacity),
                Theme.void.opacity(BlackoutTokens.Chrome.holdCardScrimOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityLabel("Close card")
        .accessibilityAddTraits(.isButton)
    }

    private func card(cappedAt cap: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            grabber
            headline
            Rectangle()
                .fill(Theme.silver.opacity(0.22))
                .frame(height: 1)
            rows
            actions
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: cap, alignment: .top)
        .background(Theme.glass())
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.accent)
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Theme.metalStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.7), radius: 18, y: -4)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var grabber: some View {
        Rectangle()
            .fill(Theme.silver.opacity(0.4))
            .frame(width: 36, height: 3)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
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
