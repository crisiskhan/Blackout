import SwiftUI
import BatteryAuction

struct InstrumentsView: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        NavigationStack {
            List {
                Button("Torch 3×") { runtime.instruments.torchTap() }
                Button("Compass cal") { runtime.instruments.calibrateCompass() }
                Button("True north") { runtime.instruments.setTrueNorth() }
                Toggle("USB-C PTT present", isOn: Binding(get: { runtime.instruments.state.usbCPTT }, set: { runtime.instruments.attachUSB_C_PTT($0) }))
                Toggle("External GNSS puck", isOn: Binding(get: { runtime.instruments.state.externalGNSS }, set: { runtime.instruments.attachGNSSPuck($0) }))
                Picker("Auction", selection: Binding(get: { runtime.power.state.mode }, set: { runtime.power.set($0) })) {
                    ForEach(PowerMode.allCases, id: \.self) { m in Text(m.rawValue.uppercased()).tag(m) }
                }
                Toggle("Pocket", isOn: Binding(get: { runtime.power.state.pocket }, set: { runtime.power.setPocket($0) }))
                Text("Hot-spare \(runtime.power.hotSparePayload())")
                Text("Screen buffer OFF default: \(!runtime.power.state.screenBuffer)")
                Button("ES / EN") { runtime.locale = runtime.locale == "es" ? "en" : "es" }
            }
            .navigationTitle("INSTRUMENTS")
            .preferredColorScheme(.dark)
        }
    }
}
