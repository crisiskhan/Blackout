import SwiftUI
import UIKit
import Tokens

/// EXPEDITION TV. SNAP stills in TRAFFIC / BRIDGE / AIRPORT / VENUE / HOP.
/// Those sections never a live stream. N/A is a 10s hold, then its own plate.
struct TvPlate: View {
    @Bindable var runtime: AppRuntime
    @State private var naHolding = false
    @State private var naPress = 0
    @State private var naStarted: Date?
    @State private var naChrome: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TV")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.5))
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Button("TAP UPDATE") {
                        runtime.pullMapSnap()
                    }
                    .buttonStyle(HUDActionStyle(filled: runtime.updateSocket.busy))
                    if !runtime.updateSocket.pipe {
                        Text("NO PIPE")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.warn)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                    }
                    if feeds.isEmpty {
                        Text("NO CAMERAS")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                    }
                }
            }
            if !runtime.naOpen { naGate }
            ForEach(openBlocks) { block in
                Text(block.kind.rawValue)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.silver.opacity(0.5))
                HUDGlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(block.feeds) { row in
                            feedRow(row)
                        }
                    }
                }
            }
        }
        .task {
            runtime.pullMapSnap()
            while !Task.isCancelled {
                let ns = UInt64(CamDesk.watchSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { return }
                if runtime.updateSocket.pipe, !runtime.updateSocket.busy {
                    runtime.pullMapSnap()
                }
            }
        }
    }

    private var you: (lat: Double, lon: Double)? {
        let pack = runtime.packs?.active
        let home = pack?.home ?? pack?.center
        return runtime.fieldYou ?? home.map { (lat: $0.lat, lon: $0.lon) }
    }

    private var feeds: [CamDesk.Feed] {
        guard let you else { return [] }
        return CamDesk.feeds(
            pack: runtime.packCams,
            hops: runtime.meshCams,
            lat: you.lat,
            lon: you.lon
        )
    }

    private var sections: [CamDesk.Section] {
        guard let you else { return [] }
        return CamDesk.sections(
            pack: runtime.packCams,
            hops: runtime.meshCams,
            lat: you.lat,
            lon: you.lon
        )
    }

    private var openBlocks: [CamDesk.Section] {
        sections
    }

    private var naGate: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("N/A")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.5))
            HUDGlassCard {
                naHoldRow
            }
        }
    }

    private var naHoldRow: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !naHolding || runtime.naOpen)) { context in
            Text(naHoldLabel(at: context.date))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(runtime.naOpen ? Color.white : Theme.warn)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !runtime.naOpen, !naHolding else { return }
                            naHolding = true
                            naChrome = nil
                            naPress &+= 1
                            let armed = naPress
                            let started = Date()
                            naStarted = started
                            DispatchQueue.main.asyncAfter(deadline: .now() + CamDesk.naHoldSeconds) {
                                let elapsed = Date().timeIntervalSince(started)
                                if naHolding, armed == naPress, CamDesk.naUnlocks(elapsed: elapsed) {
                                    runtime.openNa()
                                    naHolding = false
                                    naChrome = nil
                                }
                            }
                        }
                        .onEnded { _ in
                            if runtime.naOpen {
                                naHolding = false
                                return
                            }
                            naHolding = false
                            naStarted = nil
                            naChrome = "HOLD 10"
                        }
                )
                .accessibilityLabel("N/A")
                .accessibilityHint("HOLD 10")
                .accessibilityAddTraits(.isButton)
        }
    }

    private func naHoldLabel(at date: Date) -> String {
        if runtime.naOpen { return "N/A" }
        if naHolding, let started = naStarted {
            let left = max(0, CamDesk.naHoldSeconds - date.timeIntervalSince(started))
            if CamDesk.naUnlocks(elapsed: date.timeIntervalSince(started)) {
                return "N/A"
            }
            let seconds = max(1, Int(ceil(left)))
            return "HOLD \(seconds)"
        }
        return naChrome ?? "N/A"
    }

    private func feedRow(_ row: CamDesk.Feed) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.name)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(row.range)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
            if !row.provider.isEmpty {
                Text(row.provider.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.silver.opacity(0.7))
            }
            stillWell(id: row.id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(row.range)
    }

    private func stillWell(id: String) -> some View {
        ZStack {
            Theme.void
            if let still = still(id: id) {
                Image(uiImage: still)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 180)
            } else {
                Text("NO STILL")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 180)
        .clipShape(Theme.plateRect())
        .overlay(
            Theme.plateRect()
                .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if still(id: id) != nil {
                runtime.openStill(id: id)
            }
        }
        .accessibilityLabel(still(id: id) == nil ? "NO STILL" : "STILL")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("TAP")
    }

    private func still(id: String) -> UIImage? {
        _ = runtime.updateSocket.updatedAt
        _ = runtime.updateSocket.busy
        let url = SnapManifest.folder().appendingPathComponent("cam-\(id).jpg")
        return UIImage(contentsOfFile: url.path)
    }
}
