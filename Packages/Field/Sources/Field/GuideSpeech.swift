import AVFoundation
import BlackoutCore
import Foundation

/// Speak the next step only. On-device `AVSpeechSynthesizer`. Not the essay.
@MainActor
final class GuideSpeech {
    private let synthesizer = AVSpeechSynthesizer()

    func speakNext(_ text: String) {
        guard !text.isEmpty else { return }
        if AudioChromeLock.interruptible {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = onDeviceVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func onDeviceVoice() -> AVSpeechSynthesisVoice? {
        let language = Locale.current.identifier
        if let exact = AVSpeechSynthesisVoice(language: language) {
            return exact
        }
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice(language: code) ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}
