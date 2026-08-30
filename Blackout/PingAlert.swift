import AVFoundation
import BlackoutCore
import CoreHaptics
import UIKit

/// Inbound ping speak + hue haptic. Own outgoing pings never call this.
@MainActor
enum PingAlert {
    private static let speech = PingSpeech()

    static func announce(_ ping: LatestInboundPing, reduceMotion: Bool) {
        _ = reduceMotion
        if FieldPing.shouldSpeak(isOutbound: false) {
            speech.speak(ping.announcePhrase, rate: FieldPing.speechRate)
        }
        playHaptic(ping.ping)
    }

    static func playHaptic(_ id: FieldPingID) {
        let supports = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        guard FieldPing.shouldPlayHaptic(supportsHaptics: supports) else { return }
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch FieldPing.haptic(FieldPing.hue(id)) {
        case .light: style = .light
        case .medium: style = .medium
        case .heavy: style = .heavy
        }
        let repeats = FieldPing.hapticRepeats(id)
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.prepare()
        for index in 0..<repeats {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) {
                gen.impactOccurred()
            }
        }
    }
}

@MainActor
final class PingSpeech {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, rate: Float) {
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        synthesizer.speak(utterance)
    }
}
