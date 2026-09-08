import SwiftUI

/// Language-free circular pictograms. Same chrome as the SOS confirm bar.
public struct PictogramBar: View {
    public struct Item: Identifiable {
        public var id: String
        public var systemName: String
        public var on: Bool
        public var label: String
        public var action: () -> Void

        public init(id: String, systemName: String, on: Bool = false, label: String, action: @escaping () -> Void) {
            self.id = id
            self.systemName = systemName
            self.on = on
            self.label = label
            self.action = action
        }
    }

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 12) {
            ForEach(items) { item in
                Button(action: item.action) {
                    Image(systemName: item.systemName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(item.on ? BlackoutDS.Red.hot : BlackoutDS.Silver.metal)
                        .frame(width: BlackoutDS.Hit.sm, height: BlackoutDS.Hit.sm)
                        .background(BlackoutDS.Surface.raised)
                        .overlay(Circle().stroke(BlackoutDS.Silver.edge, lineWidth: 0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
            }
        }
    }
}
