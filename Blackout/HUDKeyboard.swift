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
        onSubmit: (() -> Void)? = nil
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
            .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            .background(Theme.glass())
            .clipShape(Theme.plateRect())
            .overlay {
                if live {
                    Theme.plateRect()
                        .strokeBorder(Theme.accent, lineWidth: 1)
                } else {
                    Theme.plateRect()
                        .strokeBorder(Theme.metalStroke, lineWidth: 1)
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
                .strokeBorder(Theme.accent, lineWidth: 1)
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
                        .strokeBorder(Theme.accent, lineWidth: 1)
                } else {
                    Theme.plateRect()
                        .strokeBorder(Theme.metalStroke, lineWidth: 1)
                }
            }
    }
}
