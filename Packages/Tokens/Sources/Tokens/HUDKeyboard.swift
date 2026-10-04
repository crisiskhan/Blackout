import Foundation

public enum HUDKeyboardLayout: Sendable {
    public static let keyHeight: Double = 44
    public static let letterRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
    ]
    public static let digitRows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["-", "0", "."],
    ]
    public static let comma = ","
    public static let apostrophe = "'"
    public static let hyphen = "-"
    public static let degree = "°"
    public static let wordKeyMinWidth: Double = 72
    public static let submitKeyMinWidth: Double = 88
}

public struct HUDKeyboardState: Equatable, Sendable {
    public var text: String
    public var shift: Bool
    public var locked: Bool
    public var face: Face

    public enum Face: String, Sendable {
        case letters, digits
    }

    public enum Key: Equatable, Sendable {
        case glyph(String)
        case space
        case back
        case shift
        case letters
        case digits
        case paste
        case done
    }

    public init(
        text: String = "",
        shift: Bool = false,
        locked: Bool = false,
        face: Face = .letters
    ) {
        self.text = text
        self.shift = shift
        self.locked = locked
        self.face = face
    }

    public mutating func tap(_ key: Key) {
        switch key {
        case .glyph(let raw):
            insert(raw)
        case .space:
            text.append(" ")
            if !locked {
                shift = true
            }
        case .back:
            if !text.isEmpty {
                text.removeLast()
            }
        case .shift:
            shift.toggle()
        case .letters:
            face = .letters
        case .digits:
            face = .digits
        case .paste, .done:
            break
        }
    }

    public mutating func paste(_ clip: String) {
        let trimmed = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        text = locked ? trimmed.uppercased() : trimmed
    }

    private mutating func insert(_ raw: String) {
        if raw.count == 1, let ch = raw.first, ch.isLetter {
            text += (locked || shift) ? raw.uppercased() : raw.lowercased()
            if !locked {
                shift = false
            }
            return
        }
        text += raw
    }
}
