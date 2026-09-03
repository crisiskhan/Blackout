import SwiftUI
import CommsUI

struct CommsTab: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMMS").foregroundStyle(Color(white: 0.85))
            HStack {
                Button("ALL") { runtime.comms.setChannel("ALL") }
                Button("1:1") { runtime.comms.setChannel("1:1") }
                Button("RADIO CHECK") { runtime.comms.radioCheck() }
            }
            HStack {
                Button(L10n.t("form.up", runtime.locale)) { runtime.comms.formUp() }
                Button(L10n.t("lost.kid", runtime.locale)) { runtime.comms.lostKid() }
                Button(L10n.t("ok.chip", runtime.locale)) { runtime.comms.chips.append(.ok) }
            }
            Text("Whisper <10 m: \(runtime.comms.whisperOK ? "yes" : "no")")
            Text("PTT live + 15 s clip. Mesh tens of meters + DTN. LoRa never required.")
                .font(.caption).foregroundStyle(Color(white: 0.55))
            Button(runtime.ptt.live ? "RELEASE PTT" : "HOLD PTT") {
                if runtime.ptt.live { runtime.ptt.endLive() } else { runtime.ptt.beginLive() }
            }
            Button("15s CLIP") {
                _ = runtime.ptt.recordClip(pcm: Data(repeating: 0, count: 32000), sampleRate: 16000)
            }
            Button(runtime.mesh.joined ? "NET JOINED" : "JOIN LOCAL NET") {
                runtime.joinNet()
            }
            ForEach(runtime.comms.chips, id: \.self) { c in
                Text(c.rawValue.uppercased()).font(.caption)
            }
            SOSHold(runtime: runtime)
            Spacer()
        }
        .padding(12)
    }
}
