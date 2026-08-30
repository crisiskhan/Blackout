import BlackoutCore
import SwiftUI

/// In-app unlock mark. Concentric metal rings drawn in SwiftUI. Not a catalog still.
public struct MetalRingLockup: View {
    private let diameter: CGFloat

    public init(diameter: CGFloat = 200) {
        self.diameter = diameter
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(BlackoutDS.Surface.raised)
            Circle()
                .stroke(BlackoutDS.Silver.metal, lineWidth: 8)
            Circle()
                .stroke(BlackoutDS.Silver.edge, lineWidth: 1)
                .padding(12)
            Circle()
                .fill(BlackoutDS.Surface.sunken)
                .padding(32)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
