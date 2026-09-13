import SwiftUI
import CommsUI
import Tokens
import MapLibreMap
import UIKit

struct CommsTab: View {
    @Bindable var runtime: AppRuntime
    @State private var scanQR = false
    @State private var pttDown = false
    @State private var note = ""

    var body: some View {
        HUDPage(
            title: "COMMS",
            status: pageStatus,
            statusTone: pageTone
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if meshSOS {
                        sosPlate
                    }

                    sectionLabel("PARTY")
                    partyCard

                    sectionLabel("FACE")
                    faceCard

                    sectionLabel("NET")
                    Button(runtime.mesh.listening ? "LEAVE NET" : "JOIN LOCAL NET") {
                        if runtime.mesh.listening {
                            runtime.leaveNet()
                        } else {
                            runtime.joinNet()
                        }
                    }
                    .buttonStyle(HUDActionStyle(filled: !runtime.mesh.listening))
                    HStack(spacing: 1) {
                        Button("ALL") { runtime.comms.setChannel("ALL") }
                            .buttonStyle(HUDDockStyle())
                        Button("1:1") {
                            if runtime.mesh.nearby.isEmpty {
                                runtime.commsChrome = "NO PEERS"
                                return
                            }
                            runtime.comms.setChannel("1:1")
                        }
                            .buttonStyle(HUDDockStyle())
                    }
                    .background(Theme.glass())
                    .clipShape(Theme.plateRect())
                    .overlay(
                        Theme.plateRect()
                            .strokeBorder(Theme.metalStroke, lineWidth: 1)
                    )
                    if !runtime.mesh.nearby.isEmpty {
                        sectionLabel("PEERS")
                        HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
                            ForEach(Array(runtime.mesh.nearby.enumerated()), id: \.offset) { _, name in
                                chip(peerWord(name)) {
                                    runtime.comms.pickPeer(name)
                                }
                            }
                        }
                    }

                    sectionLabel("CALL")
                    HStack(spacing: 1) {
                        pttPad
                        Button(runtime.clipLive ? "RECORDING" : "15s CLIP") { runtime.captureClip() }
                            .buttonStyle(HUDDockStyle())
                    }
                    .background(Theme.glass())
                    .clipShape(Theme.plateRect())
                    .overlay(
                        Theme.plateRect()
                            .strokeBorder(Theme.metalStroke, lineWidth: 1)
                    )
                    Button("RADIO CHECK") { runtime.radioCheckParty() }
                        .buttonStyle(HUDActionStyle(filled: runtime.comms.radioCheckOK && runtime.mesh.joined))
                    if !runtime.commsChrome.isEmpty {
                        Text(runtime.commsChrome)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    sectionLabel("NOTE")
                    HUDGlassCard {
                        HStack(spacing: 8) {
                            TextField("NOTE", text: $note)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.silver)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("SEND") {
                                runtime.sendPartyNote(note)
                                note = ""
                            }
                            .buttonStyle(HUDOverlayChipStyle())
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                    }

                    sectionLabel("CHIPS")
                    HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
                        chip(L10n.t("chip.rally", runtime.locale)) {
                            runtime.sendPartyChip(.rally)
                        }
                        chip(L10n.t("chip.down", runtime.locale)) {
                            runtime.sendPartyChip(.down)
                        }
                        chip(L10n.t("form.up", runtime.locale)) {
                            runtime.sendPartyChip(.formUp)
                        }
                        chip(L10n.t("lost.kid", runtime.locale)) {
                            runtime.sendPartyChip(.lostKid)
                        }
                        chip(L10n.t("chip.wait", runtime.locale)) {
                            runtime.sendPartyChip(.wait)
                        }
                        chip(L10n.t("chip.water", runtime.locale)) {
                            runtime.sendPartyChip(.water)
                        }
                    }

                    if !runtime.comms.chips.isEmpty || !runtime.mesh.inboundChips.isEmpty {
                        sectionLabel("LOG")
                        HUDGlassCard { log }
                    }
                }
            }
        }
        .sheet(isPresented: $scanQR) {
            #if canImport(AVFoundation) && canImport(UIKit)
            PartyQRScanner(
                onCode: { raw in
                    runtime.roster = runtime.roster.setting(code: PartyQR.parse(raw))
                    runtime.mesh.partyCode = runtime.roster.code
                    scanQR = false
                    runtime.joinNet()
                },
                onFail: {
                    scanQR = false
                    runtime.commsChrome = "CAMERA DENIED"
                },
                onCancel: { scanQR = false }
            )
            .ignoresSafeArea()
            .presentationBackground(Theme.void)
            #endif
        }
    }

    private var pageStatus: String {
        if runtime.ptt.live { return "PTT" }
        if runtime.clipLive { return "CLIP" }
        if runtime.comms.channel == "1:1" && !runtime.mesh.nearby.isEmpty {
            return "1:1 · \(runtime.mesh.chromeNet)"
        }
        return runtime.mesh.chromeNet
    }

    private var pageTone: HUDStatusTone {
        if runtime.hudCrisis { return .crisis }
        if runtime.mesh.joined { return .silver }
        return .warn
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
                    .background(Theme.glass())
                    .clipShape(Theme.plateRect())
                    .textInputAutocapitalization(.characters)
                    Button(L10n.t("scan.qr", runtime.locale)) { scanQR = true }
                        .buttonStyle(HUDOverlayChipStyle())
                }
                faceThumb(runtime.youEmblem, selected: true)
            }
        }
    }

    private var faceCard: some View {
        HUDGlassCard {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                spacing: 8
            ) {
                ForEach(PersonEmblem.allCases, id: \.self) { emblem in
                    Button {
                        runtime.pickEmblem(emblem)
                    } label: {
                        VStack(spacing: 4) {
                            faceThumb(emblem, selected: runtime.youEmblem == emblem)
                            Text(emblem.title)
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(Theme.silver)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                    .accessibilityLabel(emblem.title)
                }
            }
            .padding(4)
        }
    }

    private func faceThumb(_ emblem: PersonEmblem, selected: Bool) -> some View {
        let size: CGFloat = 56
        return Group {
            if let image = PersonEmblem.image(emblem) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Theme.metalLow)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(
                selected ? Theme.accent : Theme.silver.opacity(0.35),
                lineWidth: selected ? 2.4 : 1
            )
        )
        .accessibilityHidden(true)
    }

    private var pttPad: some View {
        let hit = BlackoutTokens.Chrome.mapChipHitPoints
        let liveFill = runtime.ptt.live ? Theme.silver : Theme.void
        return Text(runtime.ptt.live ? "RELEASE PTT" : "HOLD PTT")
            .font(.system(size: 12, weight: .heavy))
            .lineLimit(2)
            .minimumScaleFactor(1)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: hit, maxHeight: hit)
            .contentShape(Rectangle())
            .foregroundStyle(runtime.ptt.live ? Theme.void : Theme.silver)
            .background {
                if runtime.ptt.live {
                    liveFill
                } else {
                    Theme.glass(opacity: pttDown ? 0.55 : 0.92)
                }
            }
            .clipShape(Theme.plateRect())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pttDown {
                            pttDown = true
                            runtime.beginPTTSolo()
                        }
                    }
                    .onEnded { _ in
                        pttDown = false
                        runtime.endPTTSolo()
                    }
            )
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(runtime.comms.chips.suffix(8).enumerated()), id: \.offset) { _, c in
                Text(chipWord(c))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(c == .sos ? Theme.accent : Theme.silver)
            }
            ForEach(Array(runtime.mesh.inboundChips.suffix(8).enumerated()), id: \.offset) { _, raw in
                Text("RX · \(inboundWord(raw))")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.warn)
            }
        }
    }

    /// The hold is the trigger. This plate is the mesh seeing it — not a caption.
    private var sosPlate: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 10, height: 10)
            Text(runtime.lastConditionSOS.isEmpty ? L10n.t("sos.mesh", runtime.locale) : runtime.lastConditionSOS)
                .font(.system(size: runtime.lastConditionSOS.isEmpty ? 18 : 13, weight: .heavy))
                .foregroundStyle(Theme.accent)
                .lineLimit(2)
                .minimumScaleFactor(1)
            Spacer(minLength: 8)
            Button(L10n.t("ok.chip", runtime.locale)) { runtime.iamOK() }
                .buttonStyle(HUDOverlayChipStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.accent.opacity(0.16))
        .clipShape(Theme.plateRect())
        .overlay(
            Theme.plateRect()
                .strokeBorder(Theme.accent, lineWidth: 1.5)
        )
    }

    private var meshSOS: Bool {
        runtime.comms.chips.contains(.sos) || runtime.mesh.inboundChips.contains(Chip.sos.rawValue)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Theme.silver.opacity(0.5))
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(HUDOverlayChipStyle())
    }

    private func peerWord(_ name: String) -> String {
        name.uppercased()
    }

    private func inboundWord(_ raw: String) -> String {
        if let chip = Chip(rawValue: raw) { return chipWord(chip) }
        if raw == "ptt" { return "PTT" }
        if raw == "radio" { return "RADIO" }
        if raw.hasPrefix("field:") { return "FIELD" }
        return raw.uppercased()
    }

    private func chipWord(_ c: Chip) -> String {
        switch c {
        case .ok: return L10n.t("ok.chip", runtime.locale)
        case .formUp: return L10n.t("form.up", runtime.locale)
        case .wait: return L10n.t("chip.wait", runtime.locale)
        case .water: return L10n.t("chip.water", runtime.locale)
        case .lostKid: return L10n.t("lost.kid", runtime.locale)
        case .overdue: return L10n.t("overdue", runtime.locale)
        case .rally: return L10n.t("chip.rally", runtime.locale)
        case .down: return L10n.t("chip.down", runtime.locale)
        case .sos: return L10n.t("sos.mesh", runtime.locale)
        }
    }
}
