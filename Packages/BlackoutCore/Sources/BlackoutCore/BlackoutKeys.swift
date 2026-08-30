import Foundation

public enum BlackoutKeys {
    public static let sosArmed = "com.crisiskhan.blackout.sos.armed"
    public static let radarSweepAudio = "com.crisiskhan.blackout.radar.sweepAudio"
    public static let radarHeadingUp = "com.crisiskhan.blackout.radar.headingUp"
    public static let mapViewshed = "com.crisiskhan.blackout.map.viewshed"
    public static let mapSlope = "com.crisiskhan.blackout.map.slope"
    public static let mapTopoTiles = "com.crisiskhan.blackout.map.topoTiles"
    public static let mapTrails = "com.crisiskhan.blackout.map.trails"
    public static let navigateProfile = "com.crisiskhan.blackout.navigate.profile"
    public static let navigateMute = "com.crisiskhan.blackout.navigate.mute"
    public static let crumbsTracking = "com.crisiskhan.blackout.crumbs.tracking"
    public static let crumbsExpedition = "com.crisiskhan.blackout.crumbs.expedition"
    public static let partySelfStatus = "com.crisiskhan.blackout.party.selfStatus"
    public static let compassLockMarks = "com.crisiskhan.blackout.compassLock.marks"
    public static let meshRadioBannerDismissed = "com.crisiskhan.blackout.meshRadio.bannerDismissed"
    public static let lastUsedTBT = "com.crisiskhan.blackout.navigate.lastUsedTBT"
    public static let actionButtonHintDismissed = "com.crisiskhan.blackout.ptt.actionButtonHintDismissed"
    /// LocalIdentity blob. Format name is the key.
    public static let fieldIdentityV1 = "blackout-field-v1"
    /// Previous field blob. Copied once on first launch, then v1 is written.
    public static let fieldIdentityLegacyV3 = "redline-field-v3"
}
