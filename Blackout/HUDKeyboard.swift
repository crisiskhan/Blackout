import SwiftUI
import Observation
import Tokens

@MainActor
@Observable
final class HUDKeyboardGate {
    var activeID: String?
    var submitTitle: String = "DONE"
    var state = HUDKeyboardState()
    var onSubmit: (() -> Void)?
    var onOpen: (() -> Void)?
    private var write: ((String) -> Void)?

    var isOpen: Bool { activeID != nil }

    func open(
        id: String,
        text: String,
        submit: String,
        locked: Bool,
        digits: Bool,
        write: @escaping (String) -> Void,
        onOpen: (() -> Void)?,
        onSubmit: (() -> Void)?
    ) {
        activeID = id
        submitTitle = submit
        self.write = write
        self.onOpen = onOpen
        self.onSubmit = onSubmit
        state = HUDKeyboardState(
            text: text,
            shift: locked || !digits,
            locked: locked,
            face: digits ? .digits : .letters
        )
        onOpen?()
    }

    func tap(_ key: HUDKeyboardState.Key) {
        if case .done = key {
            onSubmit?()
            close()
            return
        }
        state.tap(key)
        write?(state.text)
    }

    func close() {
        activeID = nil
        write = nil
        onOpen = nil
        onSubmit = nil
    }

    func sync(id: String, text: String) {
        guard activeID == id, state.text != text else { return }
        state.text = text
    }
}

struct HUDField: View {
    let title: String
    @Binding var text: String
    var id: String
    var submit: String = "DONE"
    var locked: Bool = false
    var digits: Bool = false
    var pointSize: CGFloat = 14
    var weight: Font.Weight = .semibold
    var ink: Color = Theme.silver
    var onOpen: (() -> Void)? = nil
    var onSubmit: (() -> Void)? = nil
    var reserveTrailing: CGFloat = 0
    @Environment(HUDKeyboardGate.self) private var keys

    init(
        _ title: String,
        text: Binding<String>,
        id: String,
        submit: String = "DONE",
        locked: Bool = false,
        digits: Bool = false,
        pointSize: CGFloat = 14,
        weight: Font.Weight = .semibold,
        ink: Color = Theme.silver,
        onOpen: (() -> Void)? = nil,
        onSubmit: (() -> Void)? = nil,
        reserveTrailing: CGFloat = 0
    ) {
        self.title = title
        self._text = text
        self.id = id
        self.submit = submit
        self.locked = locked
        self.digits = digits
        self.pointSize = pointSize
        self.weight = weight
        self.ink = ink
        self.onOpen = onOpen
        self.onSubmit = onSubmit
        self.reserveTrailing = reserveTrailing
    }

    var body: some View {
        let live = keys.activeID == id
        Button {
            withAnimation(Theme.Motion.heavy) {
                keys.open(
                    id: id,
                    text: text,
                    submit: submit,
                    locked: locked,
                    digits: digits,
                    write: { text = $0 },
                    onOpen: onOpen,
                    onSubmit: onSubmit
                )
            }
        } label: {
            HStack(alignment: .center, spacing: 6) {
                Text(text.isEmpty ? title : text)
                    .font(.system(size: pointSize, weight: weight))
                    .foregroundStyle(text.isEmpty ? Theme.silver.opacity(0.45) : ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if live {
                    TimelineView(.animation(minimumInterval: 0.5, paused: false)) { context in
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: 2, height: pointSize + 4)
                            .opacity(Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0.15)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.trailing, reserveTrailing)
            .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            .background(Theme.glass())
            .clipShape(Theme.plateRect())
            .overlay {
                if live {
                    Theme.plateRect()
                        .strokeBorder(Theme.accent, lineWidth: Theme.strokeWidth(1))
                } else {
                    Theme.plateRect()
                        .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(text)
        .onChange(of: text) { _, now in
            keys.sync(id: id, text: now)
        }
    }
}

/// MAP SEARCH mic. Accent-red glow when idle, GNSS-green when the
/// recognizer is open. Same glass language as the field, not a chip word.
struct HUDSearchMic: View {
    var listening: Bool
    var action: () -> Void

    var body: some View {
        let ink = listening ? Theme.fix : Theme.accent
        let hit = BlackoutTokens.Chrome.mapChipHitPoints
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                let period = listening
                    ? BlackoutTokens.Chrome.destChipBeatSeconds * 0.72
                    : BlackoutTokens.Chrome.destChipBeatSeconds
                let phase = context.date.timeIntervalSinceReferenceDate / period
                let pulse = 0.5 + 0.5 * sin(phase * .pi * 2)
                let glow = listening ? 0.38 + 0.62 * pulse : 0.22 + 0.48 * pulse
                let radius = (listening ? 10.0 : 7.0) + (listening ? 10.0 : 6.0) * pulse
                HUDSearchMicArt(listening: listening, ink: ink)
                    .frame(width: 22, height: 28)
                    .shadow(color: Theme.void.opacity(0.9), radius: 2, x: 0, y: 0)
                    .shadow(color: ink.opacity(glow), radius: radius, x: 0, y: 0)
                    .shadow(color: ink.opacity(glow * 0.55), radius: radius * 1.7, x: 0, y: 0)
            }
        }
        .buttonStyle(.plain)
        .frame(width: hit, height: hit)
        .contentShape(Rectangle())
        .accessibilityLabel(listening ? "MIC ON" : "MIC")
    }
}

private struct HUDSearchMicArt: View {
    var listening: Bool
    var ink: Color

    var body: some View {
        Canvas { context, size in
            let mid = size.width / 2
            let head = CGRect(x: mid - 5.5, y: 1, width: 11, height: 15)
            if listening {
                context.fill(
                    Path(roundedRect: head, cornerRadius: 5.5),
                    with: .color(ink.opacity(0.28))
                )
            }
            context.stroke(
                Path(roundedRect: head, cornerRadius: 5.5),
                with: .color(ink),
                lineWidth: Theme.strokeWidth(1.6)
            )
            for i in 0..<3 {
                let y = head.minY + 4 + CGFloat(i) * 3.4
                var bar = Path()
                bar.move(to: CGPoint(x: mid - 3.2, y: y))
                bar.addLine(to: CGPoint(x: mid + 3.2, y: y))
                context.stroke(bar, with: .color(ink.opacity(0.88)), lineWidth: 1)
            }
            var stem = Path()
            stem.move(to: CGPoint(x: mid, y: head.maxY))
            stem.addLine(to: CGPoint(x: mid, y: head.maxY + 4.5))
            context.stroke(stem, with: .color(ink), lineWidth: Theme.strokeWidth(1.6))
            var yoke = Path()
            yoke.addArc(
                center: CGPoint(x: mid, y: head.midY + 1.5),
                radius: 7.4,
                startAngle: .degrees(28),
                endAngle: .degrees(152),
                clockwise: false
            )
            context.stroke(yoke, with: .color(ink), lineWidth: Theme.strokeWidth(1.6))
            var foot = Path()
            foot.move(to: CGPoint(x: mid - 4.5, y: size.height - 1.5))
            foot.addLine(to: CGPoint(x: mid + 4.5, y: size.height - 1.5))
            context.stroke(foot, with: .color(ink), lineWidth: Theme.strokeWidth(1.6))
        }
    }
}

struct HUDKeyboard: View {
    @Bindable var keys: HUDKeyboardGate

    var body: some View {
        VStack(spacing: 6) {
            readout
            if keys.state.face == .letters {
                letterPad
            } else {
                digitPad
            }
            actionRow
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.glass(opacity: 0.94))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.metalStroke)
                .frame(height: 1)
        }
    }

    private var readout: some View {
        HStack(spacing: 6) {
            Text(keys.state.text.isEmpty ? " " : keys.state.text)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            TimelineView(.animation(minimumInterval: 0.5, paused: false)) { context in
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 2, height: 22)
                    .opacity(Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0.15)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: CGFloat(HUDKeyboardLayout.keyHeight))
        .background(Theme.glass())
        .clipShape(Theme.plateRect())
        .overlay(
            Theme.plateRect()
                .strokeBorder(Theme.accent, lineWidth: Theme.strokeWidth(1))
        )
    }

    private var letterPad: some View {
        VStack(spacing: 6) {
            ForEach(Array(HUDKeyboardLayout.letterRows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 4) {
                    if index == 2, !keys.state.locked {
                        Button("SHIFT") { keys.tap(.shift) }
                            .buttonStyle(HUDKeyCapStyle(lit: keys.state.shift))
                            .frame(minWidth: 52)
                    }
                    ForEach(row, id: \.self) { glyph in
                        cap(shown(glyph)) { keys.tap(.glyph(glyph)) }
                    }
                    if index == 2 {
                        Button("BACK") { keys.tap(.back) }
                            .buttonStyle(HUDKeyCapStyle())
                            .frame(minWidth: 52)
                    }
                }
            }
        }
    }

    private var digitPad: some View {
        let cell = CGFloat(HUDKeyboardLayout.keyHeight)
        return VStack(spacing: 6) {
            ForEach(Array(HUDKeyboardLayout.digitRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { glyph in
                        cap(glyph) { keys.tap(.glyph(glyph)) }
                    }
                }
            }
        }
        .frame(maxWidth: cell * 3 + 12)
        .frame(maxWidth: .infinity)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            if keys.state.face == .letters {
                Button("123") { keys.tap(.digits) }
                    .buttonStyle(HUDKeyCapStyle())
                    .frame(minWidth: 52)
            } else {
                Button("ABC") { keys.tap(.letters) }
                    .buttonStyle(HUDKeyCapStyle())
                    .frame(minWidth: 52)
                Button(",") { keys.tap(.glyph(HUDKeyboardLayout.comma)) }
                    .buttonStyle(HUDKeyCapStyle())
                    .frame(minWidth: 52)
            }
            Button("SPACE") { keys.tap(.space) }
                .buttonStyle(HUDKeyCapStyle())
                .frame(maxWidth: .infinity)
            if keys.state.face == .digits {
                Button("BACK") { keys.tap(.back) }
                    .buttonStyle(HUDKeyCapStyle())
                    .frame(minWidth: 52)
            }
            Button(keys.submitTitle) { keys.tap(.done) }
                .buttonStyle(HUDKeyCapStyle(fill: Theme.accent))
                .frame(minWidth: 72)
        }
    }

    private func shown(_ glyph: String) -> String {
        guard glyph.count == 1, let ch = glyph.first, ch.isLetter else { return glyph }
        if keys.state.locked || keys.state.shift {
            return glyph.uppercased()
        }
        return glyph.lowercased()
    }

    private func cap(
        _ title: String,
        lit: Bool = false,
        wide: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(HUDKeyCapStyle(lit: lit))
            .frame(minWidth: wide ? 52 : 0)
    }
}

struct HUDKeyCapStyle: ButtonStyle {
    var lit: Bool = false
    var fill: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let hit = CGFloat(HUDKeyboardLayout.keyHeight)
        return configuration.label
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(fill == nil ? Theme.silver : Color.white)
            .frame(maxWidth: .infinity, minHeight: hit)
            .background {
                if let fill {
                    fill.opacity(configuration.isPressed ? 0.72 : 1)
                } else {
                    Theme.glass(opacity: configuration.isPressed || lit ? 0.5 : 0.92)
                }
            }
            .clipShape(Theme.plateRect())
            .overlay {
                if lit || fill != nil {
                    Theme.plateRect()
                        .strokeBorder(Theme.accent, lineWidth: Theme.strokeWidth(1))
                } else {
                    Theme.plateRect()
                        .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
                }
            }
    }
}
