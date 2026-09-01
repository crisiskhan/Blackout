import AVFoundation
import BlackoutCore
import Foundation

/// On-device `AVSpeechSynthesizer` only. No cloud TTS, no background audio session.
/// Synthesizer is created on first speak — never during Map/session init.
/// Stops speech in `deinit` so a released session cannot dealloc a live synthesizer.
final class SpeechSynthBox {
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
final class OnDeviceSpeech {
    private let box = SpeechSynthBox()

    func speak(_ text: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        guard !text.isEmpty else { return }
        let synth = box.ensure()
        if AudioChromeLock.interruptible {
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = onDeviceVoice()
        utterance.rate = rate
        synth.speak(utterance)
    }

    func stop() {
        box.stopAndNil()
    }

    func teardown() {
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
