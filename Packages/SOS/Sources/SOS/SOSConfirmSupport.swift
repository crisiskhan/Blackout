import BlackoutCore
import BlackoutLocation
import BlackoutMesh
import DesignSystem
import SwiftUI
import UIKit

@MainActor
final class SOSConfirmController {
    var location: LocationService
    var mesh: MeshFacade
    var roster: PartyRoster
    let speech = SOSSpeech()

    init(location: LocationService, mesh: MeshFacade, roster: PartyRoster) {
        self.location = location
        self.mesh = mesh
        self.roster = roster
    }

    var fix: LocationFix? { location.navigationFix }

    func perform(_ action: SOSConfirmAction, strobeOn: inout Bool) {
        switch action {
        case .speakSOS:
            speech.speak(SOSConfirm.speakSOS)
        case .speakLocation:
            speech.speak(SOSConfirm.speakLocation(fix))
        case .sharePosition:
            SOSShareSheet.present(SOSConfirm.shareMessage(fix: fix))
        case .copyCoords:
            UIPasteboard.general.string = SOSConfirm.coordsLine(fix)
        case .call911:
            signalDistress()
            openTel911()
        case .visualStrobe:
            strobeOn.toggle()
            if strobeOn {
                signalDistress()
            }
        }
    }

    func stopSpeech() {
        speech.stop()
    }

    /// Strobe start and CALL send mesh kind sos when a peer exists, and set local injury/red.
    func signalDistress() {
        if let party = roster.markInjured(fix: fix),
           SOSConfirm.shouldSendMesh(peerCount: mesh.nearbyPeerCount) {
            mesh.send(party)
        }
        guard SOSConfirm.shouldSendMesh(peerCount: mesh.nearbyPeerCount) else { return }
        mesh.send(
            SOSConfirm.meshEnvelope(sender: roster.localID, recipient: roster.recipientID)
        )
    }

    /// Opens the Phone app. The user still confirms the call. Never auto-dials.
    func openTel911() {
        guard let url = URL(string: SOSConfirm.emergencyTel) else { return }
        UIApplication.shared.open(url)
    }
}

enum SOSShareSheet {
    static func present(_ text: String) {
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        if let pop = activity.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        }
        top.present(activity, animated: true)
    }
}

struct SOSStrobeWash: View {
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: SOSConfirm.strobeInterval, paused: reduceMotion)) { context in
            let pulseOn = Int(context.date.timeIntervalSinceReferenceDate / SOSConfirm.strobeInterval) % 2 == 0
            BlackoutDS.Red.core
                .opacity(reduceMotion ? SOSConfirm.reduceMotionOpacity : (pulseOn ? 1 : 0.12))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct SOSConfirmActionList: View {
    var strobeOn: Bool
    var onAction: (SOSConfirmAction) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(SOSConfirmAction.allCases, id: \.self) { action in
                MetalButton(title(for: action), height: BlackoutDS.Hit.sm) {
                    onAction(action)
                }
            }
        }
    }

    private func title(for action: SOSConfirmAction) -> String {
        switch action {
        case .visualStrobe:
            return strobeOn ? action.stopTitle : action.title
        case .speakSOS, .speakLocation, .sharePosition, .copyCoords, .call911:
            return action.title
        }
    }
}
