import Foundation

public struct SunTimes: Equatable, Sendable { public var sunriseHour: Double; public var sunsetHour: Double }

public enum Almanac {
    /// NOAA-style approximation. Not live weather. No NWS.
    public static func sun(lat: Double, lon: Double, dayOfYear: Int) -> SunTimes {
        let decl = -23.44 * cos((360.0 / 365.0) * Double(dayOfYear + 10) * .pi / 180)
        let latR = lat * .pi / 180
        let decR = decl * .pi / 180
        let ha = acos(max(-1, min(1, -tan(latR) * tan(decR))))
        let hours = ha * 180 / .pi / 15
        let noon = 12 - lon / 15
        return SunTimes(sunriseHour: noon - hours, sunsetHour: noon + hours)
    }

    public static func shadePreferSummer(month: Int) -> Bool { (5...9).contains(month) }
}
