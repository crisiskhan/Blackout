import SwiftUI

@main
struct BlackoutWatchApp: App {
    var body: some Scene {
        WindowGroup { WatchRoot() }
    }
}

struct WatchRoot: View {
    @State private var locked = false
    @State private var ok = false
    @State private var pip = "31.76, -106.49"
    @State private var timer = "2h water"
    var body: some View {
        VStack(spacing: 8) {
            Button(locked ? "LOCKED" : "LOCK-ON") { locked.toggle() }
            Button("SOS") { }
            Button(ok ? "OK SENT" : "I AM OK") { ok = true }
            Text("PIP \(pip)").font(.caption2)
            Text("TIMER \(timer)").font(.caption2)
        }
        .preferredColorScheme(.dark)
    }
}
