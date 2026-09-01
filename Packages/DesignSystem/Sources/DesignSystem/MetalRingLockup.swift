import BlackoutCore
import SwiftUI

/// Lock-gate emblem. Crisis's lockup Image — metal ring, reticle, wordmark. Not empty Circles.
public struct MetalRingLockup: View {
    private let diameter: CGFloat

    public init(diameter: CGFloat = CGFloat(BrandChromeLock.lockupMaxPoint)) {
        self.diameter = min(diameter, CGFloat(BrandChromeLock.lockupMaxPoint))
    }

    public var body: some View {
        Image(BrandChromeLock.lockupAsset, bundle: .main)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}
