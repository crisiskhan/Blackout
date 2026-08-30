import BlackoutCore
import DesignSystem
import SwiftUI

@main
struct BlackoutApp: App {
    @State private var container = AppContainer()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView(container: container)
                    .preferredColorScheme(.dark)
                if showSplash {
                    SplashChromeView()
                }
            }
            .preferredColorScheme(.dark)
            .task {
                let nanos = UInt64(BrandChromeLock.splashHoldSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                showSplash = false
            }
        }
    }
}
