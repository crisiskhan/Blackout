import AVFoundation
import Foundation

/// On-device `AVSpeechSynthesizer` only. No cloud TTS, no background audio session.
@MainActor
final class SOSSpeech {
    private var synthesizer: AVSpeechSynthesizer?

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        let synth = synthesizer ?? AVSpeechSynthesizer()
        synthesizer = synth
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = onDeviceVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    func stop() {
        synthesizer?.stopSpeaking(at: .immediate)
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
