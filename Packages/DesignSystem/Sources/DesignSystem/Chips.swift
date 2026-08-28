import SwiftUI

public struct MeshPill: View {
    private let nearbyCount: Int

    public init(nearbyCount: Int) {
        self.nearbyCount = nearbyCount
    }

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(nearbyCount == 0 ? BlackoutDS.Silver.steel : BlackoutDS.Semantic.ok)
                .frame(width: 8, height: 8)
            Text("\(nearbyCount) nearby")
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(BlackoutDS.Surface.raised.opacity(0.82))
        .overlay(
            Capsule().stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
        .clipShape(Capsule())
        .accessibilityLabel("\(nearbyCount) nearby")
    }
}

public struct GPSChip: View {
    public enum Mode: String {
        case live = "GPS live"
        case lastKnown = "Last known"
        case compass = "Compass only"
        case denied = "GPS denied"
        case none = "No fix"
    }

    private let mode: Mode

    public init(mode: Mode) {
        self.mode = mode
    }

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(mode.rawValue)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(BlackoutDS.Surface.raised.opacity(0.82))
        .overlay(
            Capsule().stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
        .clipShape(Capsule())
    }

    private var color: Color {
        switch mode {
        case .live: return BlackoutDS.Semantic.ok
        case .lastKnown, .compass: return BlackoutDS.Semantic.warn
        case .denied, .none: return BlackoutDS.Silver.steel
        }
    }
}

public struct ScreenHeader: View {
    private let title: String
    private let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            if let subtitle {
                Text(subtitle)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
