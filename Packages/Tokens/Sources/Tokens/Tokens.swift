import Foundation

public enum BlackoutTokens: Sendable {
    public enum Chrome {
        public static let sosDiameter: Double = 64
        public static let sosHoldMs: Int = 800
        public static let tabCount: Int = 4
        public static let tabCaptionPoints: Double = 10
        public static let dynamicTypeCap: String = "xxxLarge"
        public static let oneThumbGutter: Double = 16
        /// Overlay tab strip on MAP so the canvas is the whole screen.
        public static let hudTabReservePoints: Double = 52
        /// Overlay left-hand tab column on MAP.
        public static let hudSideReservePoints: Double = 72
        public static let mapChipHitPoints: Double = 44
        /// Title-screen mark. Large enough to read as the product, not a chip.
        public static let bootLogoPoints: Double = 196
        public static let bootActivateHeight: Double = 56
        /// Even a warm launch holds the logo long enough to land, then ACTIVATE.
        public static let bootMinSeconds: Double = 0.8
        /// Overlay chips on the canvas (INST / LOCK). Fixed point size so an
        /// xxxLarge body never squeezes a word into a tail-ellipsis.
        public static let mapActionChipTextPoints: Double = 11
        public static let mapActionChipGutterPoints: Double = 10
        public static let mapActionRailSpacingPoints: Double = 6
        /// Hits shown over the map. A ScrollView on MAP is banned, so this is a hard cap.
        public static let mapSearchHitCap: Int = 5
        /// The MAP field draws short status lines only. A turn-by-turn script belongs to
        /// the voice and the route line, not to a HUD over the canvas.
        public static let fieldChromeMaxLines: Int = 3
        /// The inspect card. It grows to its content and stops at half the
        /// screen, so the pin the thumb is holding is never behind it.
        public static let holdCardMaxHeightFraction: Double = 0.5
        public static let holdCardCornerPoints: Double = 18
        /// The scrim is graded rather than flat. It has to read as "the map is
        /// not taking taps right now" everywhere, but half of the point of
        /// capping the card is that the pin stays visible, and a flat 55% wash
        /// over the top half dulls the one thing the card is about.
        public static let holdCardScrimOpacity: Double = 0.55
        public static let holdCardScrimTopOpacity: Double = 0.14
        /// How far the card has to be dragged down before it goes.
        public static let holdCardDismissDragPoints: Double = 44
        /// Field and Mark. A third button turns a glance into a menu, and SOS
        /// is never one of them — it lives on Comms and nowhere else.
        public static let holdCardMaxActions: Int = 2

        public static func sosFAB(tab: Tab, lockOn _: Bool) -> Bool {
            switch tab {
            case .comms:
                return true
            case .map, .field, .expedition:
                return false
            }
        }
    }

    public enum Color {
        public static let void = RGBA(r: 0, g: 0, b: 0, a: 1)
        public static let raised = RGBA(r: 0.09, g: 0.10, b: 0.12, a: 1)
        public static let metal = RGBA(r: 0.77, g: 0.80, b: 0.84, a: 1)
        public static let silver = metal
        public static let silverEdge = RGBA(r: 0.55, g: 0.58, b: 0.62, a: 1)
        public static let accent = RGBA(r: 225.0 / 255.0, g: 6.0 / 255.0, b: 0, a: 1)
        public static let sos = accent
        public static let nightRed = RGBA(r: 0.55, g: 0.05, b: 0.05, a: 1)
    }

    /// Offline MAP ink. Dark red/silver on void so walking-zoom streets and names read.
    public enum MapInk {
        public static let voidHex = "#000000"
        public static let silverHex = "#B8BDC2"
        public static let accentHex = "#E10600"
        public static let roadLabelMinZoom: Double = 12
        public static let roadLabelWalkingSize: Double = 19
        public static let roadLabelCloseWalkSize: Double = 22
        public static let roadLabelHaloWidth: Double = 2.2
        public static let roadLabelSpacing: Double = 100
        /// Town/neighbourhood names stop competing with street names once you are
        /// inside the block you are walking.
        public static let placeLabelMaxZoom: Double = 16
    }

    public struct RGBA: Equatable, Sendable {
        public var r, g, b, a: Double
        public init(r: Double, g: Double, b: Double, a: Double) {
            self.r = r; self.g = g; self.b = b; self.a = a
        }
    }

    public enum Tab: String, CaseIterable, Sendable {
        case map, comms, field, expedition
    }

    /// The four controls that live under the thumb on MAP. Walk and Drive
    /// still need a graph; Speak and Mark do not.
    public enum MapDock: String, CaseIterable, Sendable {
        case mark, walk, drive, speak

        public var title: String {
            switch self {
            case .mark: return "MARK"
            case .walk: return "WALK"
            case .drive: return "DRIVE"
            case .speak: return "SPEAK"
            }
        }

        public var requiresGraph: Bool {
            switch self {
            case .walk, .drive: return true
            case .mark, .speak: return false
            }
        }
    }

    /// Ruler / grid / north live with the other instruments, not on the canvas.
    public enum MapInstrument: String, CaseIterable, Sendable {
        case ruler, usng, magTrue

        public var title: String {
            switch self {
            case .ruler: return "RULER"
            case .usng: return "USNG"
            case .magTrue: return "MAG/TRUE"
            }
        }
    }

    public enum MapStillBar: String, CaseIterable, Sendable {
        case canvas = "full-height canvas"
        case outlinePuck = "pack outline+puck"
        case mark = "single MARK"
        case noSOS = "no CALL SOS on browse MAP"
        case noSlab = "no solid-red slab"

        public static var scoreBar: String {
            allCases.map { "[\($0.rawValue)]" }.joined(separator: " ")
        }
    }

    public static func conditionOnPipOnly(_ raw: String) -> Bool {
        raw == "pip"
    }
}
