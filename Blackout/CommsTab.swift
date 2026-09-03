import SwiftUI
import CommsUI

struct CommsTab: View {
    @Bindable var runtime: AppRuntime
    @State private var scanQR = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMMS").foregroundStyle(Color(white: 0.85))
            Text(runtime.mesh.chromeNet)
                .font(.caption.weight(.bold))
                .foregroundStyle(runtime.mesh.joined ? Color(white: 0.85) : Color.orange)
            HStack(alignment: .top) {
                PartyQRImage(code: runtime.roster.code)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("PARTY CODE", text: Binding(
                        get: { runtime.roster.code },
                        set: { runtime.roster = runtime.roster.setting(code: $0); runtime.mesh.partyCode = runtime.roster.code }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    Button(L10n.t("scan.qr", runtime.locale)) { scanQR = true }
                }
            }
            HStack {
                Button("ALL") { runtime.comms.setChannel("ALL") }
                Button("1:1") { runtime.comms.setChannel("1:1") }
                Button("RADIO CHECK") { runtime.comms.radioCheck() }
            }
            HStack {
                Button(L10n.t("chip.rally", runtime.locale)) {
                    runtime.comms.rally()
                    runtime.mesh.sendChip(from: runtime.mesh.localID, chip: Chip.rally.rawValue)
                }
                Button(L10n.t("chip.down", runtime.locale)) {
                    runtime.comms.down()
                    runtime.mesh.sendChip(from: runtime.mesh.localID, chip: Chip.down.rawValue)
                }
                Button(L10n.t("ok.chip", runtime.locale)) {
                    runtime.comms.chips.append(.ok)
                    runtime.mesh.sendChip(from: runtime.mesh.localID, chip: Chip.ok.rawValue)
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
            ForEach(runtime.mesh.inboundChips, id: \.self) { c in
                Text("RX \(c.uppercased())").font(.caption).foregroundStyle(Color.orange)
            }
            SOSHold(runtime: runtime)
            Spacer()
        }
        .padding(12)
        .sheet(isPresented: $scanQR) {
            #if canImport(AVFoundation) && canImport(UIKit)
            PartyQRScanner { raw in
                runtime.roster = runtime.roster.setting(code: PartyQR.parse(raw))
                runtime.mesh.partyCode = runtime.roster.code
                scanQR = false
                runtime.joinNet()
            }
            #endif
        }
    }
}
