import SwiftUI
import CommsUI
import Tokens

struct CommsTab: View {
    @Bindable var runtime: AppRuntime
    @State private var scanQR = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("COMMS")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                Spacer()
                Text(runtime.mesh.chromeNet)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(runtime.mesh.joined ? Theme.silver : Color.orange)
            }
            if meshSOS {
                sosPlate
            }
            HStack(alignment: .top, spacing: 12) {
                PartyQRImage(code: runtime.roster.code)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("PARTY CODE", text: Binding(
                        get: { runtime.roster.code },
                        set: {
                            runtime.roster = runtime.roster.setting(code: $0)
                            runtime.mesh.partyCode = runtime.roster.code
                            runtime.persistPartyCode()
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.silver)
                    .padding(.horizontal, 10)
                    .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                    .background(Theme.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .textInputAutocapitalization(.characters)
                    Button(L10n.t("scan.qr", runtime.locale)) { scanQR = true }
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                        .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                }
            }
            HStack(spacing: 8) {
                chip("ALL") { runtime.comms.setChannel("ALL") }
                chip("1:1") { runtime.comms.setChannel("1:1") }
                chip("RADIO CHECK") { runtime.comms.radioCheck() }
            }
            HStack(spacing: 8) {
                chip(L10n.t("chip.rally", runtime.locale)) {
                    runtime.comms.rally()
                    runtime.mesh.sendChip(from: runtime.mesh.localID, chip: Chip.rally.rawValue)
                }
                chip(L10n.t("chip.down", runtime.locale)) {
                    runtime.comms.down()
                    runtime.mesh.sendChip(from: runtime.mesh.localID, chip: Chip.down.rawValue)
                }
                if runtime.mesh.joined {
                    chip(L10n.t("ok.chip", runtime.locale)) {
                        runtime.iamOK()
                    }
                }
            }
            Text("Whisper <10 m: \(runtime.comms.whisperOK ? "yes" : "no")")
                .font(.caption)
                .foregroundStyle(Color(white: 0.55))
            Text(L10n.t("net.physics", runtime.locale))
                .font(.caption)
                .foregroundStyle(Color(white: 0.45))
            HStack(spacing: 8) {
                chip(runtime.ptt.live ? "RELEASE PTT" : "HOLD PTT") {
                    if runtime.ptt.live { runtime.endPTTSolo() } else { runtime.beginPTTSolo() }
                }
                chip("15s CLIP") {
                    _ = runtime.ptt.recordClip(pcm: Data(repeating: 0, count: 32000), sampleRate: 16000)
                }
            }
            Button(runtime.mesh.joined ? "NET JOINED" : "JOIN LOCAL NET") {
                runtime.joinNet()
            }
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(runtime.mesh.joined ? Theme.silver : Theme.accent)
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            .background(Theme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            ForEach(runtime.comms.chips, id: \.self) { c in
                Text(c.rawValue.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(c == .sos ? Theme.accent : Theme.silver)
            }
            ForEach(runtime.mesh.inboundChips, id: \.self) { c in
                Text("RX \(c.uppercased())")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.orange)
            }
            Spacer(minLength: 0)
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

    /// The hold is the trigger. This plate is the mesh seeing it — not a caption.
    private var sosPlate: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 10, height: 10)
            Text(L10n.t("sos.mesh", runtime.locale))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.accent)
            Spacer(minLength: 8)
            Button(L10n.t("ok.chip", runtime.locale)) { runtime.iamOK() }
                .buttonStyle(HUDOverlayChipStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.accent.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1.5)
        )
    }

    private var meshSOS: Bool {
        runtime.comms.chips.contains(.sos) || runtime.mesh.inboundChips.contains(Chip.sos.rawValue)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Theme.silver)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            .background(Theme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
