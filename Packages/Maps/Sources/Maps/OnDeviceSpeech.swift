import AVFoundation
import BlackoutCore
import Foundation

/// On-device `AVSpeechSynthesizer` only. No cloud TTS, no background audio session.
/// Synthesizer is created on first speak — never during Map/session init.
@MainActor
final class OnDeviceSpeech {
    private var synthesizer: AVSpeechSynthesizer?

    func speak(_ text: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        guard !text.isEmpty else { return }
        let synth = ensureSynthesizer()
        if AudioChromeLock.interruptible {
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = onDeviceVoice()
        utterance.rate = rate
        synth.speak(utterance)
    }

    func stop() {
        synthesizer?.stopSpeaking(at: .immediate)
    }

    private func ensureSynthesizer() -> AVSpeechSynthesizer {
        if let synthesizer { return synthesizer }
        let created = AVSpeechSynthesizer()
        synthesizer = created
        return created
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
