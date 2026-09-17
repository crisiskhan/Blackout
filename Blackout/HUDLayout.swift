import Foundation
import SwiftUI
import Tokens

struct HUDOffset: Equatable, Codable {
    var x: Double = 0
    var y: Double = 0

    var cgSize: CGSize { CGSize(width: x, height: y) }
}

struct HUDLayout: Equatable, Codable {
    var search = HUDOffset()
    var overlay = HUDOffset()
    var dock = HUDOffset()
    var footer = HUDOffset()
    var tabs = HUDOffset()
    var sos = HUDOffset()

    static let origin = HUDLayout()
    /// UserDefaults key for the persisted `hudLayout`.
    static let defaultsKey = "hud.layout"

    static func load() -> HUDLayout {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let layout = try? JSONDecoder().decode(HUDLayout.self, from: data)
        else { return .origin }
        return layout
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

enum HUDFocus: Equatable {
    case none
    case search
    case overlay
    case dock
    case footer
    case tabs
}

enum HUDPulse {
    static func opacity(awake: Bool, crisis: Bool, arranging: Bool) -> Double {
        if crisis || arranging { return 1 }
        return awake ? 1 : BlackoutTokens.Chrome.chromeAsleepOpacity
    }

    static func piece(focus: HUDFocus, piece: HUDFocus) -> Double {
        switch focus {
        case .none:
            return 1
        case .search, .overlay, .dock, .footer, .tabs:
            return focus == piece ? 1 : BlackoutTokens.Chrome.chromeDimOpacity
        }
    }
}

/// A chrome plate the thumb can drag in LAYOUT. Offsets persist.
struct HUDPlaced<Content: View>: View {
    var offset: HUDOffset
    var arranging: Bool
    var veil: Double
    var alive: Double
    var onMove: (HUDOffset) -> Void
    var onStore: () -> Void
    var content: Content
    @State private var origin: HUDOffset?

    init(
        offset: HUDOffset,
        arranging: Bool,
        veil: Double,
        alive: Double,
        onMove: @escaping (HUDOffset) -> Void,
        onStore: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.offset = offset
        self.arranging = arranging
        self.veil = veil
        self.alive = alive
        self.onMove = onMove
        self.onStore = onStore
        self.content = content()
    }

    var body: some View {
        content
            .offset(x: offset.cgSize.width, y: offset.cgSize.height)
            .opacity(veil * alive)
            .highPriorityGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard arranging else { return }
                        if origin == nil { origin = offset }
                        if let origin {
                            onMove(HUDOffset(
                                x: origin.x + value.translation.width,
                                y: origin.y + value.translation.height
                            ))
                        }
                    }
                    .onEnded { _ in
                        origin = nil
                        if arranging { onStore() }
                    },
                including: arranging ? GestureMask.gesture : .subviews
            )
    }
}
