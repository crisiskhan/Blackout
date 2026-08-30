import Foundation
import SwiftUI

public enum BlackoutDS {
    public enum Surface {
        public static let void = Color(red: 7 / 255, green: 8 / 255, blue: 10 / 255)
        public static let base = Color(red: 12 / 255, green: 14 / 255, blue: 18 / 255)
        public static let raised = Color(red: 20 / 255, green: 23 / 255, blue: 29 / 255)
        public static let overlay = Color(red: 28 / 255, green: 32 / 255, blue: 40 / 255)
        public static let sunken = Color(red: 8 / 255, green: 9 / 255, blue: 12 / 255)
        public static let hazard = Color(red: 26 / 255, green: 10 / 255, blue: 12 / 255)
    }

    public enum Red {
        public static let core = Color(red: 1, green: 43 / 255, blue: 43 / 255)
        public static let hot = Color(red: 1, green: 77 / 255, blue: 77 / 255)
        public static let sun = Color(red: 1, green: 74 / 255, blue: 74 / 255)
        public static let ember = Color(red: 196 / 255, green: 30 / 255, blue: 30 / 255)
        public static let blood = Color(red: 139 / 255, green: 20 / 255, blue: 20 / 255)
    }

    public enum Silver {
        public static let bright = Color(red: 232 / 255, green: 237 / 255, blue: 242 / 255)
        public static let mid = Color(red: 180 / 255, green: 188 / 255, blue: 198 / 255)
        public static let dim = Color(red: 122 / 255, green: 132 / 255, blue: 144 / 255)
        public static let steel = Color(red: 92 / 255, green: 101 / 255, blue: 112 / 255)
        public static let edge = Color(red: 197 / 255, green: 205 / 255, blue: 214 / 255)
        public static let metal = Color(red: 244 / 255, green: 247 / 255, blue: 250 / 255)
    }

    public enum Semantic {
        public static let ok = Color(red: 61 / 255, green: 1, blue: 154 / 255)
        public static let warn = Color(red: 1, green: 176 / 255, blue: 32 / 255)
        public static let info = Color(red: 110 / 255, green: 200 / 255, blue: 1)
    }

    /// DS v1 §10.2 navigator LOOK. Aliases only — hexes unchanged.
    public enum Map {
        public static let land = Surface.base
        public static let water = Surface.sunken
        public static let trail = Silver.dim
        public static let grid = Silver.steel
        public static let selfDot = Red.core
        public static let label: CGFloat = 12
        public static let callout: CGFloat = 16
        public static let shield: CGFloat = 24
        public static let puck: CGFloat = 36
        public static let chevron: CGFloat = 16
        public static let chevronGap: CGFloat = 12
        public static let blade: CGFloat = 10
    }

    public enum Hit {
        public static let sm: CGFloat = 56
        public static let md: CGFloat = 64
        public static let lg: CGFloat = 72
        public static let sos: CGFloat = 88
    }

    /// DS v1 §10.3 motion. Durations only — hexes unchanged.
    public enum Motion {
        public static let moveDuration: TimeInterval = 0.220
        public static let snapDuration: TimeInterval = 0.120
        public static var move: Animation { .easeInOut(duration: moveDuration) }
        public static var snap: Animation { .easeOut(duration: snapDuration) }
    }

    /// DS v1 §10.4 party vitals. Metrics and aliases only — hexes unchanged.
    public enum Vitals {
        public static let chip: CGFloat = 56
        public static let pip: CGFloat = 6
        /// 8pt: chip-to-disk gap and FAB inset above the tab bar (tabBar+8).
        public static let sosGap: CGFloat = 8
        /// Reserved height of the 88pt SOS disk band. Chip sits in this band, leading.
        public static let sosClearance: CGFloat = 88
        public static let tabBar: CGFloat = 49
        public static let homeIndicator: CGFloat = 34
    }

    /// Commit plates. `primary` is SOS/hazard fill only — vitals stay `metal`.
    public enum Btn {
        public static let metal = Silver.metal
        public static let primary = Red.core
    }

    public enum TypeMetrics {
        public static let body: CGFloat = 17
        public static let bodyLine: CGFloat = 24
        public static let floor: CGFloat = 17
    }

    public static func bodyFont() -> Font {
        .system(size: TypeMetrics.body, weight: .regular, design: .default)
    }

    public static func titleFont() -> Font {
        .system(size: 22, weight: .semibold, design: .default)
    }

    public static func captionFont() -> Font {
        .system(size: 13, weight: .medium, design: .default)
    }
}
