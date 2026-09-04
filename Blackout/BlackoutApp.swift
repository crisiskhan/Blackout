import SwiftUI

@main
struct BlackoutApp: App {
    @State private var runtime = AppRuntime()

    var body: some Scene {
        WindowGroup {
            RootChrome(runtime: runtime)
                .preferredColorScheme(.dark)
                .environment(\.dynamicTypeSize, dynamicCap(runtime))
        }
    }

    private func dynamicCap(_ runtime: AppRuntime) -> DynamicTypeSize {
        runtime.leftHand ? .xxxLarge : .xxxLarge
    }
}
