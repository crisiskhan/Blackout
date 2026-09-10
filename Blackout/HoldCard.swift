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

    /// Floor for the cap, for the one layout pass where the canvas has not been
    /// measured yet. Below this the card cannot show a headline and two
    /// buttons, and a card you cannot press is worse than a tall one.
    private static let smallestUsableCard: CGFloat = 180

    private var corner: CGFloat { CGFloat(BlackoutTokens.Chrome.holdCardCornerPoints) }

    var body: some View {
        // The cap is measured against the canvas, not the screen. The canvas is
        // the shorter of the two, and it is the one the pin is in: half a
        // 852pt screen is most of a 529pt map, so a screen-sized cap would put
        // the card back over the place the camera just lifted into view.
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
            // The drag sits on the stack rather than on the card, so a swipe
            // down over the dim map puts the card away exactly like a swipe
            // down over the card does. On the card alone, the whole top half
            // of the screen answers a swipe with nothing, and a surface that
            // ignores you is one people decide is broken.
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { drag = max(0, $0.translation.height) }
                    .onEnded { value in
                        if value.translation.height > CGFloat(BlackoutTokens.Chrome.holdCardDismissDragPoints) {
                            onClose()
                        }
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) { drag = 0 }
                    }
            )
            // Deliberately not `.isModal`. It would be the tidy thing for a
            // card over a map, and it hides everything outside its own
            // subtree from VoiceOver — including the tab bar, and Comms is on
            // the tab bar. Nothing this app puts on the screen is allowed to
            // put SOS out of reach. The scrim reads as a Close button, so
            // there is a way out without trapping anyone in here.
        }
        .transition(.opacity)
    }

    /// Heavy behind the card, nearly clear over the pin. Flat, it would dim the
    /// one place the card is talking about.
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

    /// Sized to its content until it reaches `cap`, then squeezed rather than
    /// cut off. Nothing here is `fixedSize`, so under a short canvas the
    /// sentences give up lines while the grabber and the two buttons — the
    /// only parts that have to stay hittable — keep their height.
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
            // SURE is confidence in the record.
            row(
                key: "SURE",
                value: "\(held.card.sure)%",
                note: held.card.why,
                hint: nil
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
                        .lineLimit(4)
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
                Text(held.card.kind == .water ? "FIELD · WATER" : "FIELD")
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
