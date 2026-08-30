import BlackoutCore
import MapsRouting
import SwiftUI

/// Pack, fix, and chrome observers for `MapsRootView`.
/// Kept off the sheet stack so Swift can type-check the map root.
struct MapPackLifecycleModifier: ViewModifier {
    var pack: MapsPackObservers
    var chrome: MapsChromeObservers

    func body(content: Content) -> some View {
        content
            .modifier(pack)
            .modifier(chrome)
    }
}

struct MapsPackObservers: ViewModifier {
    var outsidePack: Bool
    var fixLatitude: Double?
    var fixLongitude: Double?
    var lastKnownLatitude: Double?
    var authorization: LocationAuthorization
    var profile: NavigateProfile
    var installedPackRoots: [URL]
    var pinnedToPackCoverage: Bool
    var isCritical: Bool
    var onOutsidePack: (Bool) -> Void
    var onReloadCrumbs: () -> Void
    var onFixLatitude: () -> Void
    var onFixLongitude: () -> Void
    var onProfile: () -> Void
    var onAuthorization: () -> Void
    var onLastKnown: () -> Void
    var onInstalledRoots: () -> Void
    var onPinned: () -> Void
    var onCritical: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .modifier(MapsFixObservers(
                fixLatitude: fixLatitude,
                fixLongitude: fixLongitude,
                lastKnownLatitude: lastKnownLatitude,
                authorization: authorization,
                profile: profile,
                onFixLatitude: onFixLatitude,
                onFixLongitude: onFixLongitude,
                onProfile: onProfile,
                onAuthorization: onAuthorization,
                onLastKnown: onLastKnown
            ))
            .modifier(MapsPackStateObservers(
                outsidePack: outsidePack,
                installedPackRoots: installedPackRoots,
                pinnedToPackCoverage: pinnedToPackCoverage,
                isCritical: isCritical,
                onOutsidePack: onOutsidePack,
                onReloadCrumbs: onReloadCrumbs,
                onInstalledRoots: onInstalledRoots,
                onPinned: onPinned,
                onCritical: onCritical
            ))
    }
}

private struct MapsFixObservers: ViewModifier {
    var fixLatitude: Double?
    var fixLongitude: Double?
    var lastKnownLatitude: Double?
    var authorization: LocationAuthorization
    var profile: NavigateProfile
    var onFixLatitude: () -> Void
    var onFixLongitude: () -> Void
    var onProfile: () -> Void
    var onAuthorization: () -> Void
    var onLastKnown: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(MapsCoordinateObservers(
                fixLatitude: fixLatitude,
                fixLongitude: fixLongitude,
                lastKnownLatitude: lastKnownLatitude,
                onFixLatitude: onFixLatitude,
                onFixLongitude: onFixLongitude,
                onLastKnown: onLastKnown
            ))
            .modifier(MapsRouteObservers(
                authorization: authorization,
                profile: profile,
                onAuthorization: onAuthorization,
                onProfile: onProfile
            ))
    }
}

private struct MapsCoordinateObservers: ViewModifier {
    var fixLatitude: Double?
    var fixLongitude: Double?
    var lastKnownLatitude: Double?
    var onFixLatitude: () -> Void
    var onFixLongitude: () -> Void
    var onLastKnown: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: fixLatitude) { _, _ in onFixLatitude() }
            .onChange(of: fixLongitude) { _, _ in onFixLongitude() }
            .onChange(of: lastKnownLatitude) { _, _ in onLastKnown() }
    }
}

private struct MapsRouteObservers: ViewModifier {
    var authorization: LocationAuthorization
    var profile: NavigateProfile
    var onAuthorization: () -> Void
    var onProfile: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: authorization) { _, _ in onAuthorization() }
            .onChange(of: profile) { _, _ in onProfile() }
    }
}

private struct MapsPackStateObservers: ViewModifier {
    var outsidePack: Bool
    var installedPackRoots: [URL]
    var pinnedToPackCoverage: Bool
    var isCritical: Bool
    var onOutsidePack: (Bool) -> Void
    var onReloadCrumbs: () -> Void
    var onInstalledRoots: () -> Void
    var onPinned: () -> Void
    var onCritical: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: outsidePack) { _, outside in onOutsidePack(outside) }
            .task { onReloadCrumbs() }
            .modifier(MapsPackPinObservers(
                installedPackRoots: installedPackRoots,
                pinnedToPackCoverage: pinnedToPackCoverage,
                isCritical: isCritical,
                onInstalledRoots: onInstalledRoots,
                onPinned: onPinned,
                onCritical: onCritical
            ))
    }
}

private struct MapsPackPinObservers: ViewModifier {
    var installedPackRoots: [URL]
    var pinnedToPackCoverage: Bool
    var isCritical: Bool
    var onInstalledRoots: () -> Void
    var onPinned: () -> Void
    var onCritical: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: installedPackRoots) { _, _ in onInstalledRoots() }
            .onChange(of: pinnedToPackCoverage) { _, _ in onPinned() }
            .onChange(of: isCritical) { _, critical in onCritical(critical) }
    }
}

struct MapsChromeObservers: ViewModifier {
    var reduceMotion: Bool
    var holdsChrome: Bool
    var onAppearAction: () -> Void
    var onChromeInputs: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppearAction)
            .modifier(MapsChromeTickObservers(
                reduceMotion: reduceMotion,
                holdsChrome: holdsChrome,
                onChromeInputs: onChromeInputs
            ))
    }
}

private struct MapsChromeTickObservers: ViewModifier {
    var reduceMotion: Bool
    var holdsChrome: Bool
    var onChromeInputs: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: reduceMotion) { _, _ in onChromeInputs() }
            .onChange(of: holdsChrome) { _, _ in onChromeInputs() }
            .task(id: reduceMotion) {
                onChromeInputs()
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    onChromeInputs()
                    if reduceMotion { break }
                }
            }
    }
}
