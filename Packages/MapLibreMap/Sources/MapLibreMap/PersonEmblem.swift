import Foundation
import UIKit

/// The chosen face on YOU and on party bodies. These are person marks,
/// not overlay wildlife GPS.
public enum PersonEmblem: String, CaseIterable, Sendable, Equatable {
    case wolf
    case owl
    case bear
    case heron
    case raven
    case eagle
    case turtle
    case raccoon
    case horse
    case mule
    case beaver
    case ibex
    case roadrunner
    case muleDeer = "mule-deer"
    case husky
    case pronghorn
    case labrador
    case deer
    case falcon
    case otter
    case fox
    case boar
    case bighorn
    case bison
    case bat
    case hawk

    public static let fallback = PersonEmblem.wolf
    public static let key = "you.emblem"

    public var title: String {
        switch self {
        case .wolf: return "WOLF"
        case .owl: return "OWL"
        case .bear: return "BEAR"
        case .heron: return "HERON"
        case .raven: return "RAVEN"
        case .eagle: return "EAGLE"
        case .turtle: return "TURTLE"
        case .raccoon: return "RACCOON"
        case .horse: return "HORSE"
        case .mule: return "MULE"
        case .beaver: return "BEAVER"
        case .ibex: return "IBEX"
        case .roadrunner: return "ROADRUNNER"
        case .muleDeer: return "MULE DEER"
        case .husky: return "HUSKY"
        case .pronghorn: return "PRONGHORN"
        case .labrador: return "LABRADOR"
        case .deer: return "DEER"
        case .falcon: return "FALCON"
        case .otter: return "OTTER"
        case .fox: return "FOX"
        case .boar: return "BOAR"
        case .bighorn: return "BIGHORN"
        case .bison: return "BISON"
        case .bat: return "BAT"
        case .hawk: return "HAWK"
        }
    }

    public static func resolved(_ raw: String?) -> PersonEmblem {
        parse(raw) ?? fallback
    }

    public static func parse(_ raw: String?) -> PersonEmblem? {
        guard let raw, !raw.isEmpty else { return nil }
        return PersonEmblem(rawValue: raw)
    }

    public static func load(defaults: UserDefaults = .standard) -> PersonEmblem {
        resolved(defaults.string(forKey: key))
    }

    public static func save(_ emblem: PersonEmblem, defaults: UserDefaults = .standard) {
        defaults.set(emblem.rawValue, forKey: key)
        defaults.synchronize()
    }

    public static func image(_ emblem: PersonEmblem) -> UIImage? {
        let key = emblem.rawValue as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard
            let url = Bundle.module.url(forResource: emblem.rawValue, withExtension: "jpg"),
            let image = UIImage(contentsOfFile: url.path)
        else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private static let cache = NSCache<NSString, UIImage>()
}

/// North-up rose. The map does not rotate, so N stays screen-up and the
/// heading tick is the live instrument.
public enum PersonCompass: Sendable {
    public static let puckPoints: Double = 80
    public static let wellPoints: Double = 46
    public static let minorTickEvery = 5
    public static let majorTickEvery = 15

    public static func normalized(_ headingDeg: Double) -> Double {
        var heading = headingDeg.truncatingRemainder(dividingBy: 360)
        if heading < 0 { heading += 360 }
        return heading
    }

    public static func tickRadians(headingDeg: Double) -> Double {
        normalized(headingDeg) * .pi / 180
    }

    /// Apple marks an unusable heading with accuracy `< 0` and `-1°`.
    /// Those are not a live tick. Prefer true heading when it exists.
    public static func liveHeading(
        trueHeading: Double,
        magneticHeading: Double,
        accuracy: Double
    ) -> Double? {
        guard accuracy >= 0 else { return nil }
        if trueHeading >= 0 { return trueHeading }
        if magneticHeading >= 0 { return magneticHeading }
        return nil
    }

    public static func shortestDelta(from: Double, to: Double) -> Double {
        var delta = normalized(to) - normalized(from)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}
