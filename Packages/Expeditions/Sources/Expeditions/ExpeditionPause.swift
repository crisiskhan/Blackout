import BlackoutCore
import DesignSystem
import Foundation
import SwiftUI

/// Pause stack copy. Honest empties. No XP. No invented roster.
public enum ExpeditionPauseCopy {
    public static let title = "Pause"
    public static let subtitle = "This outing. Local only."
    public static let rosterEmpty = "Solo outing. Roster is empty."
    public static let gearStub = "No custom kit. Default outing list."
    public static let packsReady = "Florida, Texas, New York, and New Mexico are Ready on this phone. 4 states on disk."
    public static let mapBannerEmpty = "No open expedition"
    public static let sections = ["Roster", "Gear", "Packs", "Settings"]
    public static let about = "About"
}

/// GuidePack tools cards that exist on disk. Not a 17-cell inventory grid.
public enum DefaultOutingGear {
    public static let items = [
        "Headlamp",
        "Knife",
        "Cordage",
        "Ferro rod",
        "Tarp kit",
        "Repair kit"
    ]

    /// Named kit items that change Guide branches. Not on the default list.
    public static let namedKitItems = ["Tourniquet"]
}

struct OutingGearPlate: View {
    @State private var gear = OutingGearStore.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ExpeditionPauseCopy.gearStub)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
            if gear.isEmpty {
                Text("Gear list empty. Guide shows improvise steps.")
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
            }
            ForEach(DefaultOutingGear.items + DefaultOutingGear.namedKitItems, id: \.self) { item in
                Button {
                    gear.set(item, on: !gear.has(item))
                    OutingGearStore.save(gear)
                } label: {
                    HStack {
                        Text(item)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.bright)
                        Spacer()
                        Text(gear.has(item) ? "On this outing" : "Not packed")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(gear.has(item) ? BlackoutDS.Semantic.ok : BlackoutDS.Silver.dim)
                    }
                    .frame(minHeight: BlackoutDS.Hit.sm)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item)
                .accessibilityValue(gear.has(item) ? "On this outing" : "Not packed")
            }
        }
    }
}
