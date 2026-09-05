import SwiftUI
import Tokens

enum Theme {
    static var void: Color { Color(rgba: BlackoutTokens.Color.void) }
    static var accent: Color { Color(rgba: BlackoutTokens.Color.accent) }
    static var silver: Color { Color(rgba: BlackoutTokens.Color.silver) }
    static var raised: Color { Color(rgba: BlackoutTokens.Color.raised) }
}

extension Color {
    init(rgba: BlackoutTokens.RGBA) {
        self.init(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}
