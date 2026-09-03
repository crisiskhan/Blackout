import SwiftUI
import CommsUI

struct CommsTab: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMMS").foregroundStyle(Color(white: 0.85))
            Text(runtime.mesh.chromeNet)
                .font(.caption.weight(.bold))
                .foregroundStyle(runtime.mesh.joined ? Color(white: 0.85) : Color.orange)
            TextField("PARTY CODE", text: Binding(
                get: { runtime.roster.code },
                set: { runtime.roster = runtime.roster.setting(code: $0); runtime.mesh.partyCode = runtime.roster.code }
            ))
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.characters)
            HStack {
                Button("ALL") { runtime.comms.setChannel("ALL") }
                Button("1:1") { runtime.comms.setChannel("1:1") }
                Button("RADIO CHECK") { runtime.comms.radioCheck() }
            }
            HStack {
                Button(L10n.t("form.up", runtime.locale)) {
                    runtime.comms.formUp()
                    runtime.mesh.sendChip(from: runtime.roster.code, chip: Chip.formUp.rawValue)
                }
                Button(L10n.t("lost.kid", runtime.locale)) {
                    runtime.comms.lostKid()
                    runtime.mesh.sendChip(from: runtime.roster.code, chip: Chip.lostKid.rawValue)
                }
                Button(L10n.t("ok.chip", runtime.locale)) {
                    runtime.comms.chips.append(.ok)
                    runtime.mesh.sendChip(from: runtime.roster.code, chip: Chip.ok.rawValue)
                }
            }
            Text("Whisper <10 m: \(runtime.comms.whisperOK ? "yes" : "no")")
            Text(L10n.t("net.physics", runtime.locale))
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
