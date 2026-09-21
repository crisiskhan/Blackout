import SwiftUI
import CommsUI
import MeshDTN
import Tokens
import MapLibreMap
import UIKit

private enum CommsPlate: String, CaseIterable {
    case party, net, call, note, chips

    var title: String {
        switch self {
        case .party: return "PARTY"
        case .net: return "NET"
        case .call: return "CALL"
        case .note: return "NOTE"
        case .chips: return "CHIPS"
        }
    }
}

struct CommsTab: View {
    @Bindable var runtime: AppRuntime
    @State private var scanQR = false
    @State private var pttDown = false
    @State private var note = ""
    @State private var plate: CommsPlate = .party

    var body: some View {
        HUDPage(
            title: "COMMS",
            status: pageStatus,
            statusTone: pageTone
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if meshSOS {
                    sosPlate
                }
                plateRail
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        plateBody
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .overlay {
            if scanQR {
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
                .transition(.opacity)
                #endif
            }
        }
        .animation(Theme.Motion.heavy, value: scanQR)
        .onAppear {
            if runtime.pendingNoteFocus { plate = .note }
            openPendingNote()
        }
        .onChange(of: runtime.pendingNoteFocus) { _, now in
            if now { plate = .note }
            openPendingNote()
        }
    }

    private var plateRail: some View {
        HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
            ForEach(CommsPlate.allCases, id: \.self) { item in
                Button(item.title) { plate = item }
                    .buttonStyle(HUDOverlayChipStyle(filled: plate == item))
            }
        }
    }

    @ViewBuilder
    private var plateBody: some View {
        switch plate {
        case .party:
            sectionLabel("PARTY")
            partyCard
        case .net:
            netPlate
        case .call:
            callPlate
        case .note:
            notePlate
        case .chips:
            chipsPlate
        }
    }

    private var netPlate: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("NET")
            Button(runtime.mesh.joined ? "LEAVE NET" : "JOIN LOCAL NET") {
                if runtime.mesh.joined {
                    runtime.leaveNet()
                } else {
                    runtime.joinNet()
                }
            }
            .buttonStyle(HUDActionStyle(filled: !runtime.mesh.joined))
            Button("SCAN") { runtime.scanMesh() }
                .buttonStyle(HUDActionStyle(filled: runtime.mesh.placing))
            Button(runtime.mesh.listening ? "QUIET" : "LISTEN") {
                if runtime.mesh.listening {
                    runtime.quietRadio()
                } else {
                    runtime.listenNet()
                }
            }
            .buttonStyle(HUDActionStyle(filled: runtime.mesh.listening && !runtime.mesh.joined))
            if !runtime.commsChrome.isEmpty {
                Text(runtime.commsChrome)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !runtime.mesh.chromeNear.isEmpty {
                Text(runtime.mesh.chromeNear)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.fix)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !runtime.mesh.chromeSignal.isEmpty {
                Text(runtime.mesh.chromeSignal)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.fix)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 1) {
                Button("ALL") { runtime.comms.setChannel("ALL") }
                    .buttonStyle(HUDDockStyle())
                Button("1:1") {
                    if runtime.mesh.nearby.isEmpty && runtime.comms.peer != "YOU" {
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
                    .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
            )
            sectionLabel("PEERS")
            HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
                chip(peerWord("YOU")) {
                    runtime.comms.pickPeer("YOU")
                }
                ForEach(Array(runtime.mesh.nearby.enumerated()), id: \.offset) { _, name in
                    if name != "YOU" {
                        chip(peerWord(name)) {
                            runtime.comms.pickPeer(name)
                        }
                    }
                }
            }
        }
    }

    private var callPlate: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("CALL")
            HStack(spacing: 1) {
                pttPad
                Button(runtime.clipLive ? "RECORDING" : "15s CLIP") { runtime.captureClip() }
                    .buttonStyle(HUDDockStyle())
                Button("PLAY") { runtime.playLastClip() }
                    .buttonStyle(HUDDockStyle())
            }
            .background(Theme.glass())
            .clipShape(Theme.plateRect())
            .overlay(
                Theme.plateRect()
                    .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
            )
            Button("RADIO CHECK") { runtime.radioCheckParty() }
                .buttonStyle(HUDActionStyle(filled: runtime.comms.radioCheckOK && runtime.mesh.joined))
            if !runtime.commsChrome.isEmpty {
                Text(runtime.commsChrome)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notePlate: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("NOTE")
            HUDGlassCard {
                HStack(spacing: 8) {
                    HUDField("NOTE", text: $note, id: "comms.note", submit: "SEND") {
                        if runtime.sendPartyNote(note) {
                            note = ""
                        }
                    }
                    Button("SEND") {
                        if runtime.sendPartyNote(note) {
                            note = ""
                            runtime.hudKeys.close()
                        }
                    }
                    .buttonStyle(HUDOverlayChipStyle())
                }
                .padding(.horizontal, 10)
                .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            }
        }
    }

    private var chipsPlate: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("CHIPS")
            HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
                ForEach(Chip.rail, id: \.self) { c in
                    chip(L10n.t(c.wordKey, runtime.locale)) {
                        runtime.sendPartyChip(c)
                    }
                }
            }
            if !runtime.comms.chips.isEmpty || !runtime.mesh.inboundChips.isEmpty {
                sectionLabel("LOG")
                HUDGlassCard { log }
            }
        }
    }

    private var pageStatus: String {
        if runtime.ptt.live { return "PTT" }
        if runtime.clipLive { return "CLIP" }
        if runtime.comms.channel == "1:1" {
            if runtime.comms.peer == "YOU" {
                return "1:1 · YOU"
            }
            if !runtime.mesh.nearby.isEmpty {
                return "1:1 · \(runtime.mesh.chromeNet)"
            }
        }
        var bits = [runtime.mesh.chromeNet, runtime.mesh.chromeNear, runtime.mesh.chromeSignal]
            .filter { !$0.isEmpty }
        if runtime.commsChrome == "SCAN — NO FIX" {
            bits.insert(runtime.commsChrome, at: 0)
        }
        return bits.joined(separator: " · ")
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
                    HUDField("PARTY CODE",
                        text: Binding(
                            get: { runtime.roster.code },
                            set: {
                                runtime.roster = runtime.roster.setting(code: $0)
                                runtime.mesh.partyCode = runtime.roster.code
                                runtime.persistPartyCode()
                            }
                        ),
                        id: "comms.party",
                        locked: true
                    )
                    Button(L10n.t("scan.qr", runtime.locale)) { scanQR = true }
                        .buttonStyle(HUDOverlayChipStyle())
                }
                faceThumb(runtime.youEmblem, selected: true)
            }
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
                .strokeBorder(Theme.accent, lineWidth: Theme.strokeWidth(1.5))
        )
    }

    private var meshSOS: Bool {
        runtime.comms.chips.contains(.sos) || runtime.mesh.inboundChips.contains(Chip.sos.rawValue)
    }

    private func openPendingNote() {
        guard runtime.pendingNoteFocus else { return }
        runtime.pendingNoteFocus = false
        runtime.hudKeys.open(
            id: "comms.note",
            text: note,
            submit: "SEND",
            locked: false,
            digits: false,
            write: { note = $0 },
            onOpen: nil,
            onSubmit: {
                if runtime.sendPartyNote(note) {
                    note = ""
                }
            }
        )
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
        L10n.t(c.wordKey, runtime.locale)
    }
}
