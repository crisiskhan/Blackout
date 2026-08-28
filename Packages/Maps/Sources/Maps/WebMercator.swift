import Foundation

enum WebMercator {
    static func tileX(longitude: Double, zoom: Int) -> Double {
        (longitude + 180.0) / 360.0 * pow(2.0, Double(zoom))
    }

    static func tileY(latitude: Double, zoom: Int) -> Double {
        let lat = min(max(latitude, -85.05112878), 85.05112878)
        let latRad = lat * .pi / 180
        return (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * pow(2.0, Double(zoom))
    }

    static func longitude(tileX: Double, zoom: Int) -> Double {
        tileX / pow(2.0, Double(zoom)) * 360.0 - 180.0
    }

    static func latitude(tileY: Double, zoom: Int) -> Double {
        let n = .pi - 2.0 * .pi * tileY / pow(2.0, Double(zoom))
        return 180.0 / .pi * atan(0.5 * (exp(n) - exp(-n)))
    }
}
