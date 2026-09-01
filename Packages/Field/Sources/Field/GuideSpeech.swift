import AVFoundation
import BlackoutCore
import Foundation

/// Speak the next step only. On-device `AVSpeechSynthesizer`. Not the essay.
/// Synthesizer is created on first speak — never during Field/view init.
/// Stops speech in `deinit` so a released Field plate cannot dealloc a live synthesizer.
final class GuideSynthBox {
    private var synthesizer: AVSpeechSynthesizer?

    func ensure() -> AVSpeechSynthesizer {
        if let synthesizer { return synthesizer }
        let created = AVSpeechSynthesizer()
        synthesizer = created
        return created
    }

    func stopAndNil() {
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
    }

    deinit {
        stopAndNil()
    }
}

@MainActor
final class GuideSpeech {
    private let box = GuideSynthBox()

    func speakNext(_ text: String) {
        guard !text.isEmpty else { return }
        let synth = box.ensure()
        if AudioChromeLock.interruptible {
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = onDeviceVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    func stop() {
        box.stopAndNil()
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
