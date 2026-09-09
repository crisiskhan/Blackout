import Foundation

/// When a finger on the map means "tell me about this" and when it means "move".
///
/// The map already owns pan, pinch, rotate and a single tap that picks a
/// destination. Inspect has to fit between them without taking anything away,
/// so it is the one thing none of the others are: a finger that stays put.
///
/// UIKit enforces `allowableMovementPoints` itself — a press that drifts past it
/// before the clock runs out never recognises, so a drag pans and nothing else.
/// The same rule is written here as a plain function because that is the part
/// worth testing without a touch screen.
public enum InspectGesture {
    /// Long enough that it cannot be a tap, short enough to feel deliberate.
    public static let minimumPressSeconds: Double = 0.45
    /// Roughly a thumb's roll. The map's own pan starts around ten points, so a
    /// press that is really a pan loses this race well before the clock.
    public static let allowableMovementPoints: Double = 12

    public enum Verdict: Equatable, Sendable {
        /// Still down, still still, clock not up.
        case waiting
        /// Open the card.
        case inspect
        /// The finger moved. This is the map being moved, not a question.
        case pan
    }

    public static func verdict(elapsedSeconds: Double, movedPoints: Double) -> Verdict {
        if movedPoints > allowableMovementPoints { return .pan }
        return elapsedSeconds >= minimumPressSeconds ? .inspect : .waiting
    }

    public static func moved(dx: Double, dy: Double) -> Double {
        (dx * dx + dy * dy).squareRoot()
    }
}

/// How much room the inspect card is allowed, and how to keep the pressed point
/// out from under it.
public enum InspectCard {
    /// Half the glass, never more. The map is the point; the card is the answer.
    public static let maxHeightFraction: Double = 0.5
    /// Clearance between the pin and the top edge of the card.
    public static let pinMarginPoints: Double = 44

    public static func maxHeight(screenHeight: Double) -> Double {
        max(0, screenHeight * maxHeightFraction)
    }

    /// How far the map content must slide up so the pin the press dropped stays
    /// on screen above the card. Zero when it already is.
    public static func liftPoints(
        pressY: Double,
        screenHeight: Double,
        cardHeight: Double
    ) -> Double {
        let covered = min(cardHeight, maxHeight(screenHeight: screenHeight))
        let ceiling = screenHeight - covered - pinMarginPoints
        guard ceiling > 0 else { return 0 }
        return max(0, pressY - ceiling)
    }
}

/// The inspect pin: where the press landed, drawn so the card is talking about
/// somewhere the eye can still find.
public enum InspectPin {
    public static let sourceID = "inspect-pin-src"
    public static let ringLayerID = "inspect-pin-ring"
    public static let coreLayerID = "inspect-pin-core"
    public static let ringRadius: Double = 17
    public static let coreRadius: Double = 5

    public static func needsReapply(
        stored: (lat: Double, lon: Double)?,
        pin: (lat: Double, lon: Double)?
    ) -> Bool {
        switch (stored, pin) {
        case (nil, nil):
            return false
        case let (a?, b?):
            return abs(a.lat - b.lat) > 1e-9 || abs(a.lon - b.lon) > 1e-9
        default:
            return true
        }
    }
}
