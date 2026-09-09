import SwiftUI
import MapLibreMap
import Tokens

/// The place the thumb is holding, and what the pack says is there.
struct HeldPoint: Equatable {
    var lat: Double
    var lon: Double
    var card: Inspect.Card
    /// Set once MARK has been pressed, so the card can show it took.
    var marked = false
}

/// Dark glass over the canvas: what this is, how sure the record is, what to
/// do, and two ways to act on it. Tapping the dim map or dragging the card
/// down puts it away. There is no SOS here and there never will be — SOS is a
/// Comms button, and a thumb resting on a map is not a call for help.
struct HoldCardView: View {
    let held: HeldPoint
    let onField: () -> Void
    let onMark: () -> Void
    let onClose: () -> Void

    @State private var drag: CGFloat = 0

    private var corner: CGFloat { CGFloat(BlackoutTokens.Chrome.holdCardCornerPoints) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.void
                .opacity(BlackoutTokens.Chrome.holdCardScrimOpacity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityLabel("Close card")
                .accessibilityAddTraits(.isButton)
            card
                .offset(y: max(0, drag))
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { drag = $0.translation.height }
                        .onEnded { value in
                            if value.translation.height > CGFloat(BlackoutTokens.Chrome.holdCardDismissDragPoints) {
                                onClose()
                            }
                            drag = 0
                        }
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var card: some View {
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: capHeight, alignment: .top)
        .background(glass)
        .overlay(alignment: .top) {
            // One red hairline so the card reads as this app's and not as a
            // system sheet. The card's own clip rounds its ends.
            Rectangle()
                .fill(Theme.accent)
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Theme.silver.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.7), radius: 18, y: -4)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    /// Blur plus a black wash. The blur alone would let bright streets through
    /// and the text would fight them.
    private var glass: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Theme.void.opacity(0.74))
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(Theme.silver.opacity(0.4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(held.card.title)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(held.card.klass.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(
                key: "SURE",
                value: "\(held.card.sure)%",
                note: held.card.why,
                hint: "Confidence in the record, not in the water."
            )
            row(key: "DO", value: nil, note: held.card.doLine, hint: nil)
            if let date = held.card.packDate {
                row(key: "PACK", value: date, note: nil, hint: nil)
            }
        }
    }

    private func row(key: String, value: String?, note: String?, hint: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.75))
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if let value {
                    Text(value)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                if let note {
                    Text(note)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.silver)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint ?? "")
    }

    /// Two, and only two. `holdCardMaxActions` is the contract a guard reads.
    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onField) {
                Text("FIELD")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HoldActionStyle(filled: false))
            Button(action: onMark) {
                Text(held.marked ? "MARKED" : "MARK")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HoldActionStyle(filled: held.marked))
        }
    }

    private var capHeight: CGFloat {
        let screen = UIScreen.main.bounds.height
        return max(180, screen * CGFloat(BlackoutTokens.Chrome.holdCardMaxHeightFraction))
    }
}

private struct HoldActionStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(filled ? Color.white : Theme.silver)
            .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            .contentShape(Rectangle())
            .background(filled ? Theme.accent : Theme.raised)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.silver.opacity(filled ? 0 : 0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
