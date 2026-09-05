import SwiftUI

struct ARMINGView: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityLabel("Blackout")
            Text("ARMING").font(.title.weight(.semibold)).foregroundStyle(Theme.silver)
            Text("Offline vessel. No account. No uplink.")
                .foregroundStyle(Color(white: 0.65))
            if let packs = runtime.packs {
                ForEach(packs.catalog.packs, id: \.id) { p in
                    Button("\(p.name)  ·  \(p.bytes / 1024) KB") {
                        runtime.switchPack(p.id)
                    }
                    .foregroundStyle(Theme.silver)
                }
            } else {
                Text("Packs missing from bundle — honest empty.").foregroundStyle(Color(white: 0.5))
            }
            Toggle("Left-hand column", isOn: $runtime.leftHand)
                .tint(Theme.accent)
            Toggle("Night-red", isOn: Binding(get: { runtime.night.enabled }, set: { runtime.night.enabled = $0 }))
                .tint(Theme.accent)
            Button("INITIATE") { runtime.arm() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.accent)
                .foregroundStyle(Theme.silver)
        }
        .padding(24)
    }
}
