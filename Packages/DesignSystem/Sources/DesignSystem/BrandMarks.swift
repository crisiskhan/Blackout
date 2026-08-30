import BlackoutCore
import SwiftUI

/// Locked wordmark from the app catalog. Never SF Pro BLACKOUT. Never the lockup.
public struct BrandWordmark: View {
    private let maxWidth: CGFloat

    public init(maxWidth: CGFloat) {
        self.maxWidth = maxWidth
    }

    public var body: some View {
        Image(BrandChromeLock.wordmarkAsset, bundle: .main)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .accessibilityLabel("Blackout")
    }
}

/// Locked red-eye O crop. Original rendering. Not a template. Not an SF Symbol.
public struct RedEyeOMark: View {
    private let point: CGFloat

    public init(point: CGFloat) {
        self.point = point
    }

    public var body: some View {
        Image(BrandChromeLock.redEyeOAsset, bundle: .main)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: point, height: point)
            .accessibilityHidden(true)
    }
}

/// Wordmark only, centered on void. Hold is owned by the app shell. No pulse on the O.
public struct SplashChromeView: View {
    public init() {}

    public var body: some View {
        ZStack {
            BlackoutDS.Surface.void.ignoresSafeArea()
            BrandWordmark(maxWidth: CGFloat(BrandChromeLock.splashWordmarkMaxWidth))
        }
        .accessibilityLabel("Blackout")
    }
}

/// Existing wordmark above callsign. Not the lockup.
public struct AboutChromeView: View {
    private let callsign: String

    public init(callsign: String) {
        self.callsign = callsign
    }

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()
            BrandWordmark(maxWidth: CGFloat(BrandChromeLock.aboutWordmarkMaxWidth))
            Text(callsign)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
                .accessibilityLabel("Callsign \(callsign)")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(BlackoutDS.Surface.void.ignoresSafeArea())
        .navigationTitle(BrandChromeLock.aboutTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
