import BlackoutBattery
import BlackoutCore
import BlackoutLocation
import BlackoutMesh
import DesignSystem
import SwiftUI

public struct SettingsRootView: View {
    @Bindable var battery: BatteryService
    @Bindable var location: LocationService
    @Bindable var mesh: MeshFacade
    @Bindable var lock: AppLockService
    private let callsign: String

    public init(
        battery: BatteryService,
        location: LocationService,
        mesh: MeshFacade,
        lock: AppLockService,
        callsign: String = Callsign.defaultValue,
        onFieldPacks: (() -> Void)? = nil
    ) {
        self.battery = battery
        self.location = location
        self.mesh = mesh
        self.lock = lock
        self.callsign = callsign
        self.onFieldPacks = onFieldPacks
    }

    private let onFieldPacks: (() -> Void)?
    @State private var showAbout = false

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenHeader("Settings", subtitle: "Local only. No account. No analytics.")
                    fieldPacksBlock
                    batteryBlock
                    locationBlock
                    lockBlock
                    meshBlock
                    privacyBlock
                    limitsBlock
                    aboutBlock
                }
                .padding(20)
                .padding(.bottom, 120)
            }
            .background(BlackoutDS.Surface.base.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $showAbout) {
                AboutChromeView(callsign: callsign)
            }
        }
    }

    private var aboutBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            GhostButton(BrandChromeLock.aboutTitle, height: BlackoutDS.Hit.sm) {
                showAbout = true
            }
        }
    }

    private var fieldPacksBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Field Packs")
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            Text("Open the Packs plate to Get a city or Update maps on Wi-Fi. Ready is disk-only. DefaultPack stays the Denver fallback.")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
            if let onFieldPacks {
                GhostButton("Open Packs plate", height: BlackoutDS.Hit.sm, action: onFieldPacks)
            }
        }
    }

    private var batteryBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Battery")
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            Text(levelCopy)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
            if battery.isCritical {
                Text("Last ~2% is SOS-only. Map, Comms, Field, and Expedition unmount. The SOS FAB stays. This is not Extreme Saver.")
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Red.hot)
            }
            ForEach(BatteryPolicy.allCases) { policy in
                Button {
                    battery.policy = policy
                    location.applyPolicy(policy)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(policy.title)
                                .foregroundStyle(BlackoutDS.Silver.bright)
                            Text(policy.detail)
                                .font(BlackoutDS.captionFont())
                                .foregroundStyle(BlackoutDS.Silver.dim)
                        }
                        Spacer()
                        if battery.policy == policy {
                            Image(systemName: "checkmark")
                                .foregroundStyle(BlackoutDS.Silver.metal)
                        }
                    }
                    .padding(14)
                    .frame(minHeight: BlackoutDS.Hit.sm)
                    .background(BlackoutDS.Surface.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var locationBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location")
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            Text("First launch does not require this. Deny is a supported field state.")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
            if location.authorization == .denied || location.authorization == .restricted {
                PermissionDenied(
                    kind: .location,
                    reason: "GPS denied. Last-known and compass-only remain. Guide, Skills, bundled map, and SOS stay usable."
                )
            } else if location.authorization == .notDetermined {
                MetalButton("Allow location when in use") {
                    location.requestWhenInUse()
                    location.startUpdating()
                }
            } else {
                Text("Authorized. Coarse Navigate remains on in Extreme Saver. Last ~2% hides it (SOS-only).")
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Semantic.ok)
            }
        }
    }

    private var lockBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy / security")
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            Toggle(isOn: $lock.isEnabled) {
                Text("Local lock")
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
            }
            .tint(BlackoutDS.Silver.metal)
            .frame(height: BlackoutDS.Hit.sm)
            Text("Face ID / passcode on this device. No iCloud. No analytics.")
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
        }
    }

    private var meshBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mesh")
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            MeshPill(nearbyCount: mesh.nearbyPeerCount)
            Text("Local radio, no WAN, no account. One nearby phone can take a sealed message. Zero nearby is calm success. Stranger Radar stays off.")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
        }
    }

    private var privacyBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data")
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            Text("Expeditions, breadcrumbs, SOS events, and sealed messages stay in SwiftData on this device. Message bodies are ciphertext. CloudKit is off. There is no account.")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.mid)
                .lineSpacing(7)
        }
    }

    private var limitsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This pass")
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            Text("Mesh is one nearby phone on the same local radio — no WAN, no account, no N>1 routing. No world map, no auto-911, no fall detection, no backend. DefaultPack is a generated Front Range sample, not a USGS extract.")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.mid)
                .lineSpacing(7)
        }
    }

    private var levelCopy: String {
        let pct = battery.level < 0 ? "—" : "\(Int(battery.level * 100))%"
        let charge = battery.isCharging ? "charging" : "unplugged"
        return "\(pct) · \(charge)"
    }
}

public struct LockGateView: View {
    @Bindable var lock: AppLockService
    @State private var failed = false

    public init(lock: AppLockService) {
        self.lock = lock
    }

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Blackout")
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            Text("On-device lock. Nothing to sign in to.")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
            MetalButton("Unlock", height: BlackoutDS.Hit.lg) {
                Task {
                    let ok = await lock.unlock()
                    failed = !ok
                }
            }
            if failed {
                PermissionDenied(
                    kind: .localAuthentication,
                    reason: "Device authentication failed or is unavailable. Data stays on disk; it was not uploaded."
                )
                .padding(.horizontal, 20)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlackoutDS.Surface.void.ignoresSafeArea())
    }
}
