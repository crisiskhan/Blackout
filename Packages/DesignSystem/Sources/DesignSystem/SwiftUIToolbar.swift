import SwiftUI

extension View {
    /// SwiftUI `toolbar(content:)`. MapKit declares the same name on `View`;
    /// files that `import Maps` (and therefore MapKit) must call this instead.
    public func swiftUIToolbar<Content: ToolbarContent>(
        @ToolbarContentBuilder content: () -> Content
    ) -> some View {
        toolbar(content: content)
    }
}
