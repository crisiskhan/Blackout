import DesignSystem
import MapsRouting
import SwiftUI

struct NavigatePreviewCard: View {
    @Binding var profile: NavigateProfile
    var route: Route
    var label: String
    var attribution: String?
    var canStart: Bool
    var noGPS: Bool
    var onStart: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                profileChip(.walk)
                profileChip(.drive)
            }
            Text(label)
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            Text("\(Formatters.distance(route.distanceMeters)) · \(Formatters.eta(route.etaSeconds))")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.mid)
            if let first = route.maneuvers.first(where: { $0.kind != .arrive }) {
                Text(VoicePrompt.phrase(for: first, distanceMeters: first.distanceMeters))
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
            }
            if noGPS {
                Text(NavigateCopy.noGPS)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Semantic.warn)
            }
            if let attribution, !attribution.isEmpty {
                Text(attribution)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.steel)
            }
            HStack(spacing: 8) {
                GhostButton("Cancel", height: BlackoutDS.Hit.sm, action: onCancel)
                MetalButton("Start", height: BlackoutDS.Hit.sm, action: onStart)
                    .opacity(canStart ? 1 : 0.45)
                    .disabled(!canStart)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BlackoutDS.Surface.raised.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func profileChip(_ value: NavigateProfile) -> some View {
        Button {
            profile = value
        } label: {
            Text(title(value))
                .font(BlackoutDS.captionFont())
                .fontWeight(.semibold)
                .foregroundStyle(profile == value ? BlackoutDS.Surface.void : BlackoutDS.Silver.bright)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(profile == value ? BlackoutDS.Silver.metal : BlackoutDS.Surface.raised)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func title(_ value: NavigateProfile) -> String {
        switch value {
        case .walk: return "Walk"
        case .drive: return "Drive"
        }
    }
}

struct NavigateGuidanceBar: View {
    var tick: GuidanceTick?
    var route: Route?
    var muted: Bool
    var noGPS: Bool
    var onMute: () -> Void
    var onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(street)
                        .font(BlackoutDS.titleFont())
                        .foregroundStyle(BlackoutDS.Silver.bright)
                    Text(turnDistance)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.mid)
                }
                Spacer(minLength: 8)
                Text(eta)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
            }
            if noGPS {
                Text(NavigateCopy.noGPS)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Semantic.warn)
            }
            HStack(spacing: 8) {
                GhostButton(muted ? "Unmute" : "Mute", height: BlackoutDS.Hit.sm, action: onMute)
                GhostButton("End", height: BlackoutDS.Hit.sm, action: onEnd)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BlackoutDS.Surface.raised.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var street: String {
        tick?.nextManeuver?.streetName ?? "Continue"
    }

    private var turnDistance: String {
        guard let tick else { return "—" }
        return Formatters.distance(tick.distanceToTurnMeters)
    }

    private var eta: String {
        Formatters.eta(tick?.etaSeconds ?? route?.etaSeconds ?? 0)
    }
}

struct NavigateEmptyCard: View {
    var empty: NavigateEmpty
    var onBearing: () -> Void
    var onPacks: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(empty.title)
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            if let body = empty.body {
                Text(body)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.mid)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if empty == .noGraph || empty == .packTooNew {
                if empty == .noGraph {
                    GhostButton(NavigateCopy.bearingOnly, height: BlackoutDS.Hit.md, action: onBearing)
                }
                if let onPacks {
                    MetalButton(NavigateCopy.packManager, height: BlackoutDS.Hit.md, action: onPacks)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 400, alignment: .leading)
        .background(BlackoutDS.Surface.raised)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct NavigateHitsList: View {
    var hits: [PackSearchHit]
    var onPick: (PackSearchHit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(hits) { hit in
                Button {
                    onPick(hit)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.title)
                                .font(BlackoutDS.bodyFont())
                                .foregroundStyle(BlackoutDS.Silver.bright)
                            Text(hit.kind)
                                .font(BlackoutDS.captionFont())
                                .foregroundStyle(BlackoutDS.Silver.dim)
                        }
                        Spacer()
                        if let meters = hit.meters {
                            Text(Formatters.distance(meters))
                                .font(BlackoutDS.captionFont())
                                .foregroundStyle(BlackoutDS.Silver.mid)
                        }
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(BlackoutDS.Surface.raised.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
