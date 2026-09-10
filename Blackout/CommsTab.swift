import SwiftUI
import CommsUI
import Tokens

struct CommsTab: View {
    @Bindable var runtime: AppRuntime
    @State private var scanQR = false

    var body: some View {
        HUDPage(
            title: "COMMS",
            status: runtime.mesh.chromeNet,
            warn: !runtime.mesh.joined
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if meshSOS {
                        sosPlate
                    }
                    partyCard
                    HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
                        chip("ALL") { runtime.comms.setChannel("ALL") }
                        chip("1:1") { runtime.comms.setChannel("1:1") }
                        chip("RADIO CHECK") { runtime.comms.radioCheck() }
                    }
                    HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
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
                    HStack(spacing: 1) {
                        Button(runtime.ptt.live ? "RELEASE PTT" : "HOLD PTT") {
                            if runtime.ptt.live { runtime.endPTTSolo() } else { runtime.beginPTTSolo() }
                        }
                        .buttonStyle(HUDDockStyle())
                        Button("15s CLIP") {
                            _ = runtime.ptt.recordClip(pcm: Data(repeating: 0, count: 32000), sampleRate: 16000)
                        }
                        .buttonStyle(HUDDockStyle())
                    }
                    .background(Theme.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.silver.opacity(0.22), lineWidth: 1)
                    )
                    Button(runtime.mesh.joined ? "NET JOINED" : "JOIN LOCAL NET") {
                        runtime.joinNet()
                    }
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(runtime.mesh.joined ? Theme.silver : Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                    .background(Theme.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    log
                }
            }
        }
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

    private var partyCard: some View {
        HUDGlassCard {
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
                        .buttonStyle(HUDOverlayChipStyle())
                }
            }
        }
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            .buttonStyle(HUDOverlayChipStyle())
    }
}
