import SwiftUI

struct ARMINGView: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ARMING").font(.title.weight(.semibold)).foregroundStyle(Color(white: 0.85))
            Text("Offline vessel. No account. No uplink.")
                .foregroundStyle(Color(white: 0.65))
            if let packs = runtime.packs {
                ForEach(packs.catalog.packs, id: \.id) { p in
                    Button("\(p.name)  ·  \(p.bytes / 1024) KB") {
                        runtime.switchPack(p.id)
                    }
                    .foregroundStyle(Color(white: 0.8))
                }
            } else {
                Text("Packs missing from bundle — honest empty.").foregroundStyle(Color(white: 0.5))
            }
            Toggle("Left-hand column", isOn: $runtime.leftHand)
            Toggle("Night-red", isOn: Binding(get: { runtime.night.enabled }, set: { runtime.night.enabled = $0 }))
            Button("ENTER") { runtime.arm() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(white: 0.18))
                .foregroundStyle(Color(white: 0.9))
        }
        .padding(24)
    }
}
