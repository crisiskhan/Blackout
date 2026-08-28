import BlackoutCore
import BlackoutBattery
import BlackoutLocation
import DesignSystem
import SwiftUI

struct NavigateView: View {
    @Bindable var location: LocationService
    var pack: MapPackSnapshot?
    @Bindable var battery: BatteryService
    @State private var selected: MapPOI?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    "Navigate",
                    subtitle: battery.isCritical
                        ? "Coarse Navigate is off at ~2% battery. SOS stays."
                        : "Coarse bearing. Extreme Saver does not disable this."
                )
                if battery.isCritical {
                    Text("Last-2% is SOS-only. Radar HUD and coarse nav are hidden. The SOS FAB stays.")
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Red.hot)
                } else {
                    if battery.isExtremeSaver {
                        Text("Extreme Saver · coarse only")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Semantic.warn)
                    }
                    if location.authorization == .denied || location.authorization == .restricted {
                        PermissionDenied(
                            kind: .location,
                            reason: "No live GPS. Bearing uses last-known or a manual pin. Compass-only still paints a heading. The app does not wait on a fix."
                        )
                    }
                    HUDPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(bearingCopy)
                                .font(BlackoutDS.bodyFont())
                            if let heading = location.headingDegrees {
                                Text("Compass \(Int(heading))°")
                                    .foregroundStyle(BlackoutDS.Silver.mid)
                            }
                        }
                    }
                    ForEach(pack?.pois ?? []) { poi in
                        Button {
                            selected = poi
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(poi.name)
                                        .foregroundStyle(BlackoutDS.Silver.bright)
                                    Text(poi.kind)
                                        .font(BlackoutDS.captionFont())
                                        .foregroundStyle(BlackoutDS.Silver.dim)
                                }
                                Spacer()
                                Text(rangeCopy(to: poi))
                                    .font(BlackoutDS.captionFont())
                                    .foregroundStyle(BlackoutDS.Silver.mid)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .navigationTitle("Navigate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bearingCopy: String {
        guard let selected, let from = location.navigationFix, from.hasCoordinate else {
            if selected == nil { return "Pick a pack point. No network routing." }
            return "No coordinate to compute a bearing. Drop a manual pin on the map."
        }
        let brg = bearing(
            fromLat: from.latitude!, fromLon: from.longitude!,
            toLat: selected.latitude, toLon: selected.longitude
        )
        return "Bearing to \(selected.name): \(Int(brg))°"
    }

    private func rangeCopy(to poi: MapPOI) -> String {
        guard let from = location.navigationFix, from.hasCoordinate else { return "—" }
        let meters = haversine(
            from.latitude!, from.longitude!,
            poi.latitude, poi.longitude
        )
        if meters > 1000 { return String(format: "%.1f km", meters / 1000) }
        return String(format: "%.0f m", meters)
    }
}

func bearing(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Double {
    let φ1 = fromLat * .pi / 180
    let φ2 = toLat * .pi / 180
    let Δλ = (toLon - fromLon) * .pi / 180
    let y = sin(Δλ) * cos(φ2)
    let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
    let θ = atan2(y, x)
    return (θ * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}

func haversine(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let r = 6_371_000.0
    let φ1 = lat1 * .pi / 180
    let φ2 = lat2 * .pi / 180
    let Δφ = (lat2 - lat1) * .pi / 180
    let Δλ = (lon2 - lon1) * .pi / 180
    let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
    return 2 * r * atan2(sqrt(a), sqrt(1 - a))
}
