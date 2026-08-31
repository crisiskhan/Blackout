import BlackoutCore
import BlackoutBattery
import BlackoutLocation
import BlackoutMesh
import DesignSystem
import SwiftUI
import UIKit

public struct SOSFab: View {
    @Bindable var location: LocationService
    let persistence: any PersistenceServing
    @Bindable var mesh: MeshFacade
    @Bindable var battery: BatteryService
    @Bindable var roster: PartyRoster

    @State private var showConfirm = false
    @State private var isArmed = false
    @State private var showArmedPanel = false
    @State private var storeError: String?
    var presentConfirm: Binding<Bool>?
    var coverOpen: Binding<Bool>?
    var suppressPersistedArmedAutoPresent: Bool
    var showsDisk: Bool

    private static let armedKey = BlackoutKeys.sosArmed

    public init(
        location: LocationService,
        persistence: any PersistenceServing,
        mesh: MeshFacade,
        battery: BatteryService,
        roster: PartyRoster,
        presentConfirm: Binding<Bool>? = nil,
        coverOpen: Binding<Bool>? = nil,
        suppressPersistedArmedAutoPresent: Bool = false,
        showsDisk: Bool = true
    ) {
        self.location = location
        self.persistence = persistence
        self.mesh = mesh
        self.battery = battery
        self.roster = roster
        self.presentConfirm = presentConfirm
        self.coverOpen = coverOpen
        self.suppressPersistedArmedAutoPresent = suppressPersistedArmedAutoPresent
        self.showsDisk = showsDisk
        _isArmed = State(initialValue: UserDefaults.standard.bool(forKey: Self.armedKey))
    }

    public var body: some View {
        Group {
            if showsDisk {
                disk
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .fullScreenCover(isPresented: $showConfirm) {
            SOSConfirmCover(
                location: location,
                mesh: mesh,
                roster: roster,
                storeError: $storeError,
                onArm: arm,
                onDismissUnarmed: { showConfirm = false }
            )
        }
        .fullScreenCover(isPresented: $showArmedPanel) {
            SOSArmedPanel(
                location: location,
                mesh: mesh,
                roster: roster,
                onDismiss: { showArmedPanel = false }
            )
        }
        .opacity(showsDisk && battery.hidesSOS ? 0 : 1)
        .allowsHitTesting(!showsDisk || !battery.hidesSOS)
        .overlay(alignment: .top) {
            if let storeError, !showConfirm, !showArmedPanel, showsDisk {
                StoreFailure(storeError)
                    .frame(width: 280)
                    .offset(y: -120)
            }
        }
        .onAppear { consumePresentConfirm() }
        .onChange(of: presentConfirm?.wrappedValue ?? false) { _, requested in
            if requested { consumePresentConfirm() }
        }
        .onChange(of: showConfirm) { _, _ in publishCover() }
        .onChange(of: showArmedPanel) { _, _ in publishCover() }
    }

    private var disk: some View {
        Button(action: {}) {
            ZStack {
                Circle()
                    .fill(BlackoutDS.Red.core)
                Circle()
                    .stroke(isArmed ? BlackoutDS.Silver.metal : BlackoutDS.Red.hot, lineWidth: 3)
                Text("SOS")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(BlackoutDS.Silver.metal)
            }
            .frame(width: BlackoutDS.Hit.sos, height: BlackoutDS.Hit.sos)
            .shadow(color: BlackoutDS.Red.blood.opacity(0.55), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("SOS. Hold to arm.")
        .simultaneousGesture(
            LongPressGesture(minimumDuration: SOSChrome.holdSeconds)
                .onEnded { _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if isArmed {
                        showArmedPanel = true
                    } else {
                        showConfirm = true
                    }
                }
        )
    }

    private func arm() {
        let fix = location.navigationFix
        let event = SOSEventRecordDTO(
            armedAt: Date(),
            latitude: fix?.latitude,
            longitude: fix?.longitude,
            note: "Armed offline. Party peers: \(roster.peerCount)."
        )
        do {
            try persistence.logSOS(event)
        } catch {
            storeError = error.localizedDescription
            return
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        isArmed = true
        UserDefaults.standard.set(true, forKey: Self.armedKey)
        showConfirm = false
        showArmedPanel = true
        storeError = nil
        if SOSConfirm.shouldSendMesh(peerCount: mesh.nearbyPeerCount) {
            mesh.send(
                SOSConfirm.meshEnvelope(
                    sender: roster.localID,
                    recipient: roster.recipientID,
                    callsign: roster.identity.callsign
                )
            )
        }
    }

    private func consumePresentConfirm() {
        guard presentConfirm?.wrappedValue == true else { return }
        if showsDisk {
            if isArmed {
                if SOSArmedRestore.shouldAutoPresentArmedOverlay(
                    persistedArmed: true,
                    presentRequested: true,
                    newBinaryLaunch: suppressPersistedArmedAutoPresent
                ) {
                    showArmedPanel = true
                }
            } else {
                showConfirm = true
            }
        } else {
            showConfirm = true
        }
        presentConfirm?.wrappedValue = false
    }

    private func publishCover() {
        coverOpen?.wrappedValue = showConfirm || showArmedPanel
    }
}

public struct SOSConfirmCover: View {
    @Bindable var location: LocationService
    @Bindable var mesh: MeshFacade
    @Bindable var roster: PartyRoster
    @Binding var storeError: String?
    var onArm: () -> Void
    var onDismissUnarmed: () -> Void
    @State private var strobeOn = false
    @State private var controller: SOSConfirmController?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        GeometryReader { geo in
            let thumbHeight = geo.size.height * CGFloat(SOSChrome.confirmThumbZone)
            ZStack {
                BlackoutDS.Surface.hazard.ignoresSafeArea()
                if strobeOn {
                    SOSStrobeWash(reduceMotion: reduceMotion)
                }
                VStack(spacing: 0) {
                    VStack {
                        Spacer(minLength: 24)
                        RedEyeOMark(point: CGFloat(BrandChromeLock.sosConfirmRedEye))
                            .clipShape(Circle())
                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)

                    VStack(spacing: 16) {
                        SlideToConfirm(
                            SOSChrome.confirmPhrase,
                            knobStyle: SOSChrome.confirmKnobIsSOS ? .sos : .metal,
                            knobSize: CGFloat(SOSChrome.confirmHit)
                        ) {
                            controller?.stopSpeech()
                            onArm()
                        }
                        CrisisLockActionStrip(strobeOn: strobeOn) { control in
                            handle(control)
                        }
                        if let storeError {
                            StoreFailure(storeError)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                    .frame(height: thumbHeight, alignment: .bottom)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SOS confirm. Slide to arm. Tap never fires.")
        .preferredColorScheme(.dark)
        .onAppear { bindController() }
        .onDisappear {
            controller?.stopSpeech()
            strobeOn = false
        }
    }

    private func handle(_ control: SOSCrisisLockControl) {
        switch control {
        case .cancel:
            controller?.stopSpeech()
            strobeOn = false
            onDismissUnarmed()
        case .strobe, .speakCoords, .share, .call911:
            if let action = control.confirmAction {
                perform(action)
            }
        }
    }

    private func bindController() {
        controller = SOSConfirmController(location: location, mesh: mesh, roster: roster)
    }

    private func perform(_ action: SOSConfirmAction) {
        if controller == nil { bindController() }
        controller?.perform(action, strobeOn: &strobeOn)
    }
}

public struct SOSArmedPanel: View {
    var location: LocationService
    @Bindable var mesh: MeshFacade
    @Bindable var roster: PartyRoster
    var onDismiss: () -> Void
    @State private var strobeOn = false
    @State private var showSystemSOS = false
    @State private var controller: SOSConfirmController?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            BlackoutDS.Surface.hazard.ignoresSafeArea()
            if strobeOn {
                SOSStrobeWash(reduceMotion: reduceMotion)
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("SOS armed")
                    .font(BlackoutDS.titleFont())
                    .foregroundStyle(BlackoutDS.Red.hot)
                Text("Logged on-device. Party peers: \(roster.peerCount). Closing this panel does not disarm. The alert already went out locally.")
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.mid)
                    .lineSpacing(7)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        SOSConfirmActionList(strobeOn: strobeOn) { action in
                            perform(action)
                        }
                        MeshPill(nearbyCount: mesh.nearbyPeerCount)
                        MetalButton("Emergency SOS (system)", height: BlackoutDS.Hit.lg) {
                            showSystemSOS = true
                        }
                        Text("Never auto-dials 911. You start the OS Emergency SOS gesture.")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.steel)
                    }
                }
            }
            .padding(24)
            Button {
                dismissWithoutDisarming()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BlackoutDS.Silver.bright)
                    .frame(width: BlackoutDS.Hit.sm, height: BlackoutDS.Hit.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close. Does not disarm.")
            .padding(.trailing, 12)
            .padding(.top, 12)
            .safeAreaPadding(.top)
        }
        .sheet(isPresented: $showSystemSOS) {
            SystemEmergencySOSView()
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            controller?.stopSpeech()
            strobeOn = false
        }
    }

    private func bindController() {
        controller = SOSConfirmController(location: location, mesh: mesh, roster: roster)
    }

    private func perform(_ action: SOSConfirmAction) {
        if controller == nil { bindController() }
        controller?.perform(action, strobeOn: &strobeOn)
    }

    private func dismissWithoutDisarming() {
        controller?.stopSpeech()
        strobeOn = false
        // Closing does not write BlackoutKeys.sosArmed. Product keeps the arm.
        onDismiss()
    }
}

/// Apple does not publish a URL that programmatically invokes Emergency SOS.
/// This is the user-initiated OS flow (side + volume). Never tel:911.
public struct SystemEmergencySOSView: View {
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader("Emergency SOS", subtitle: "System flow on this iPhone / iPad.")
            Text("Press and hold the side button and a volume button until the Emergency SOS slider appears. Slide it. That is the OS flow — Blackout will not place the call.")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.mid)
                .lineSpacing(7)
            Text("If Medical ID is configured in the OS, that screen can appear from the same hardware gesture.")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
                .lineSpacing(7)
            Spacer()
        }
        .padding(24)
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
    }
}

public struct SOSLogView: View {
    let persistence: any PersistenceServing
    @State private var events: [SOSEventRecordDTO] = []
    @State private var storeError: String?

    public init(persistence: any PersistenceServing) {
        self.persistence = persistence
    }

    public var body: some View {
        List {
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.armedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(BlackoutDS.Silver.bright)
                    Text(event.latitude == nil ? "No GPS fix" : "Fix stored")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.dim)
                    Text(event.note)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                }
                .listRowBackground(BlackoutDS.Surface.raised)
            }
        }
        .scrollContentBackground(.hidden)
        .background(BlackoutDS.Surface.base)
        .navigationTitle("SOS log")
        .safeAreaInset(edge: .top) {
            if let storeError {
                StoreFailure(storeError).padding(16)
            }
        }
        .task {
            do {
                events = try persistence.sosEvents()
                storeError = nil
            } catch {
                storeError = error.localizedDescription
            }
        }
    }
}
