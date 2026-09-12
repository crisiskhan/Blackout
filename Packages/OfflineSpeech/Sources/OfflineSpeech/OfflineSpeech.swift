import Foundation
import BlackBox
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Speech) && os(iOS)
import Speech
#endif

public final class SpeechEngine: @unchecked Sendable {
    public private(set) var lastUtterance: String = ""
    public private(set) var lastFailed = false
    public private(set) var listening = false
    private let box: EventLog
    #if canImport(AVFoundation)
    private var synth: AVSpeechSynthesizer?
    #endif
    #if canImport(Speech) && os(iOS)
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceWork: DispatchWorkItem?
    private var capWork: DispatchWorkItem?
    private var heard = ""
    private var pendingDone: ((String) -> Void)?
    #endif

    public init(box: EventLog) { self.box = box }

    @discardableResult
    public func speak(_ text: String, locale: String) -> Bool {
        cancelListen()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastFailed = true
            lastUtterance = "SPEECH FAILED"
            box.log("speech", "SPEECH FAILED")
            return false
        }
        #if canImport(AVFoundation)
        let engine = synth ?? AVSpeechSynthesizer()
        synth = engine
        if engine.isSpeaking {
            engine.stopSpeaking(at: .immediate)
        }
        let u = AVSpeechUtterance(string: trimmed)
        u.voice = AVSpeechSynthesisVoice(language: locale == "es" ? "es-MX" : "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        u.preUtteranceDelay = 0.12
        u.postUtteranceDelay = 0.2
        engine.speak(u)
        lastFailed = false
        lastUtterance = "\(locale):\(trimmed)"
        box.log("speech", lastUtterance)
        return true
        #else
        lastFailed = true
        lastUtterance = "SPEECH FAILED"
        box.log("speech", "SPEECH FAILED")
        return false
        #endif
    }

    /// On-device dictation for SEARCH. Never Apple servers. False when Speech
    /// is missing, the locale cannot run on-device, or listen is already live.
    @discardableResult
    public func listen(locale: String, then done: @escaping (String) -> Void) -> Bool {
        #if canImport(Speech) && os(iOS)
        if listening { return false }
        let lang = locale == "es" ? "es-MX" : "en-US"
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted:
            return false
        case .notDetermined:
            listening = true
            pendingDone = done
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch status {
                    case .authorized:
                        if !self.beginListen(lang: lang, done: done) {
                            self.finishListen(text: "")
                        }
                    case .denied, .restricted, .notDetermined:
                        self.finishListen(text: "")
                    @unknown default:
                        self.finishListen(text: "")
                    }
                }
            }
            return true
        case .authorized:
            return beginListen(lang: lang, done: done)
        @unknown default:
            return false
        }
        #else
        _ = locale
        _ = done
        return false
        #endif
    }

    /// Second SAY tap: end the buffer so the hypothesis can finalize.
    public func endListen() {
        #if canImport(Speech) && os(iOS)
        recognitionRequest?.endAudio()
        #endif
    }

    #if canImport(Speech) && os(iOS)
    private func beginListen(lang: String, done: @escaping (String) -> Void) -> Bool {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: lang)),
              rec.isAvailable,
              rec.supportsOnDeviceRecognition
        else { return false }
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            return false
        case .undetermined:
            listening = true
            pendingDone = done
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        if !self.startRecognizer(rec, done: done) {
                            self.finishListen(text: "")
                        }
                    } else {
                        self.finishListen(text: "")
                    }
                }
            }
            return true
        case .granted:
            return startRecognizer(rec, done: done)
        @unknown default:
            return false
        }
    }

    private func startRecognizer(_ rec: SFSpeechRecognizer, done: @escaping (String) -> Void) -> Bool {
        stopListenHardware()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { return false }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
        audioEngine = engine
        recognitionRequest = req
        pendingDone = done
        heard = ""
        listening = true
        recognitionTask = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.heard = result.bestTranscription.formattedString
                if result.isFinal {
                    self.finishListen(text: self.heard)
                    return
                }
                self.armSilence()
            }
            if error != nil {
                self.finishListen(text: self.heard)
            }
        }
        let cap = DispatchWorkItem { [weak self] in
            self?.recognitionRequest?.endAudio()
        }
        capWork = cap
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: cap)
        return true
    }

    private func armSilence() {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.recognitionRequest?.endAudio()
        }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func finishListen(text: String) {
        guard pendingDone != nil else { return }
        let cb = pendingDone
        pendingDone = nil
        listening = false
        silenceWork?.cancel()
        capWork?.cancel()
        silenceWork = nil
        capWork = nil
        heard = ""
        stopListenHardware()
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        box.log("say", spoken.isEmpty ? "SAY FAILED" : spoken)
        DispatchQueue.main.async {
            cb?(spoken)
        }
    }

    private func cancelListen() {
        pendingDone = nil
        listening = false
        silenceWork?.cancel()
        capWork?.cancel()
        silenceWork = nil
        capWork = nil
        heard = ""
        stopListenHardware()
    }

    private func stopListenHardware() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
    }
    #else
    private func cancelListen() {}
    #endif
}
