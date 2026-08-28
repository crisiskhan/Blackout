import SwiftUI

/// Commit controls use metal, never red. Red is live/danger/SOS only.
public struct MetalButton: View {
    private let title: String
    private let height: CGFloat
    private let action: () -> Void

    public init(_ title: String, height: CGFloat = BlackoutDS.Hit.md, action: @escaping () -> Void) {
        self.title = title
        self.height = height
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(BlackoutDS.bodyFont())
                .fontWeight(.semibold)
                .foregroundStyle(BlackoutDS.Surface.void)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(BlackoutDS.Silver.metal)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

public struct GhostButton: View {
    private let title: String
    private let height: CGFloat
    private let action: () -> Void

    public init(_ title: String, height: CGFloat = BlackoutDS.Hit.sm, action: @escaping () -> Void) {
        self.title = title
        self.height = height
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

public struct HazardFill: View {
    public init() {}

    public var body: some View {
        BlackoutDS.Surface.void
            .ignoresSafeArea()
    }
}
