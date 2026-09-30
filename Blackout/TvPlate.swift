import SwiftUI
import UIKit
import Tokens

/// EXPEDITION TV. SNAP stills nearest to farthest. Never a live stream.
struct TvPlate: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TV")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.5))
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Button("TAP UPDATE") { runtime.pullMapSnap() }
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
                    ForEach(feeds) { row in
                        feedRow(row)
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

    private var feeds: [CamDesk.Feed] {
        let pack = runtime.packs?.active
        let home = pack?.home ?? pack?.center
        let you = runtime.fieldYou ?? home.map { (lat: $0.lat, lon: $0.lon) }
        guard let you else { return [] }
        return CamDesk.feeds(
            pack: runtime.packCams,
            hops: runtime.meshCams,
            lat: you.lat,
            lon: you.lon
        )
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
        .accessibilityLabel(still(id: id) == nil ? "NO STILL" : "STILL")
    }

    private func still(id: String) -> UIImage? {
        _ = runtime.updateSocket.updatedAt
        _ = runtime.updateSocket.busy
        let url = SnapManifest.folder().appendingPathComponent("cam-\(id).jpg")
        return UIImage(contentsOfFile: url.path)
    }
}
