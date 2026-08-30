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

    @State private var showConfirm = false
    @State private var isArmed = false
    @State private var showArmedPanel = false
    @State private var storeError: String?
    var presentConfirm: Binding<Bool>?
    var coverOpen: Binding<Bool>?

    private static let armedKey = BlackoutKeys.sosArmed

    public init(
        location: LocationService,
        persistence: any PersistenceServing,
        mesh: MeshFacade,
        battery: BatteryService,
        presentConfirm: Binding<Bool>? = nil,
        coverOpen: Binding<Bool>? = nil
    ) {
        self.location = location
        self.persistence = persistence
        self.mesh = mesh
        self.battery = battery
        self.presentConfirm = presentConfirm
        self.coverOpen = coverOpen
        _isArmed = State(initialValue: UserDefaults.standard.bool(forKey: Self.armedKey))
    }

    public var body: some View {
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
            LongPressGesture(minimumDuration: 1.5)
                .onEnded { _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if isArmed {
                        showArmedPanel = true
                    } else {
                        showConfirm = true
                    }
                }
        )
        .fullScreenCover(isPresented: $showConfirm) {
            SOSConfirmCover(
                meshCount: mesh.nearbyPeerCount,
                storeError: $storeError,
                onArm: arm,
                onDismissUnarmed: { showConfirm = false }
            )
        }
        .fullScreenCover(isPresented: $showArmedPanel) {
            SOSArmedPanel(
                meshCount: mesh.nearbyPeerCount,
                onDismiss: { showArmedPanel = false }
            )
        }
        .opacity(battery.hidesSOS ? 0 : 1)
        .allowsHitTesting(!battery.hidesSOS)
        .overlay(alignment: .top) {
            if let storeError, !showConfirm, !showArmedPanel {
                StoreFailure(storeError)
                    .frame(width: 280)
                    .offset(y: -120)
            }
        }
        .onChange(of: presentConfirm?.wrappedValue ?? false) { _, requested in
            if requested {
                if isArmed {
                    showArmedPanel = true
                } else {
                    showConfirm = true
                }
                presentConfirm?.wrappedValue = false
            }
        }
        .onChange(of: showConfirm) { _, _ in publishCover() }
        .onChange(of: showArmedPanel) { _, _ in publishCover() }
    }

    private func arm() {
        let fix = location.navigationFix
        let event = SOSEventRecordDTO(
            armedAt: Date(),
            latitude: fix?.latitude,
            longitude: fix?.longitude,
            note: "Armed offline. Mesh peers: \(mesh.nearbyPeerCount)."
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
        let envelope = Envelope(
            kind: .sosAlert,
            ciphertext: Data("sos".utf8),
            sender: BlackoutID(),
            recipient: BlackoutID()
        )
        if mesh.nearbyPeerCount > 0 {
            mesh.send(envelope)
        }
    }

    private func publishCover() {
        coverOpen?.wrappedValue = showConfirm || showArmedPanel
    }
}

public struct SOSConfirmCover: View {
    var meshCount: Int
    @Binding var storeError: String?
    var onArm: () -> Void
    var onDismissUnarmed: () -> Void
    @State private var sirenOn = false
    @State private var strobeOn = false
    @State private var flashWhite = false
    @State private var showSystemSOS = false

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            (flashWhite ? Color.white : BlackoutDS.Surface.hazard).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text("SOS")
                    .font(BlackoutDS.titleFont())
                    .foregroundStyle(BlackoutDS.Red.hot)
                Text("Unarmed. Holding the button only opened this cover. Slide to arm, log, and alert peers when they exist.")
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.mid)
                    .lineSpacing(7)
                SOSPictogramBar(
                    onSiren: {
                        SOSLocalSignals.shared.toggleSiren()
                        sirenOn = SOSLocalSignals.shared.sirenRunning
                    },
                    onStrobe: {
                        SOSLocalSignals.shared.onStrobeTick = { flashWhite = $0 }
                        SOSLocalSignals.shared.toggleStrobe()
                        strobeOn = SOSLocalSignals.shared.strobeRunning
                    },
                    onSystemSOS: { showSystemSOS = true },
                    onCancel: {
                        SOSLocalSignals.shared.stopAll()
                        onDismissUnarmed()
                    },
                    sirenOn: sirenOn,
                    strobeOn: strobeOn
                )
                MeshPill(nearbyCount: meshCount)
                SlideToConfirm("Slide to arm") {
                    SOSLocalSignals.shared.stopAll()
                    onArm()
                }
                if let storeError {
                    StoreFailure(storeError)
                }
                Text("Pictograms are local siren, strobe, OS Emergency SOS, cancel. Slide still arms. Blackout never auto-dials 911.")
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.steel)
                Spacer()
            }
            .padding(24)
            Button {
                SOSLocalSignals.shared.stopAll()
                onDismissUnarmed()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BlackoutDS.Silver.bright)
                    .frame(width: BlackoutDS.Hit.sm, height: BlackoutDS.Hit.sm)
            }
            .padding(12)
        }
        .sheet(isPresented: $showSystemSOS) {
            SystemEmergencySOSView()
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
        }
        .preferredColorScheme(.dark)
        .onDisappear { SOSLocalSignals.shared.stopAll() }
    }
}

public struct SOSArmedPanel: View {
    var meshCount: Int
    var onDismiss: () -> Void
    @State private var showSystemSOS = false

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            BlackoutDS.Surface.hazard.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text("SOS armed")
                    .font(BlackoutDS.titleFont())
                    .foregroundStyle(BlackoutDS.Red.hot)
                Text("Logged on-device. Mesh peers: \(meshCount). Closing this panel does not disarm. The alert already went out locally.")
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.mid)
                    .lineSpacing(7)
                MeshPill(nearbyCount: meshCount)
                MetalButton("Emergency SOS (system)", height: BlackoutDS.Hit.lg) {
                    showSystemSOS = true
                }
                Text("Never auto-dials 911. You start the OS Emergency SOS gesture.")
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.steel)
                Spacer()
            }
            .padding(24)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BlackoutDS.Silver.bright)
                    .frame(width: BlackoutDS.Hit.sm, height: BlackoutDS.Hit.sm)
            }
            .padding(12)
        }
        .sheet(isPresented: $showSystemSOS) {
            SystemEmergencySOSView()
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
        }
        .preferredColorScheme(.dark)
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
