import AVFoundation
import BlackoutCore
import DesignSystem
import Speech
import SwiftUI

/// 56pt metal mic on the compose bar. System speech into the text field. Not PTT.
struct ComposeDictationButton: View {
    @Binding var text: String
    var enabled: Bool
    var onDenied: () -> Void

    @State private var listening = false
    @State private var denied = false
    @State private var recognizer: SFSpeechRecognizer?
    @State private var request: SFSpeechAudioBufferRecognitionRequest?
    @State private var task: SFSpeechRecognitionTask?
    @State private var engine: AVAudioEngine?
    @State private var prefix = ""

    var body: some View {
        Button(action: toggle) {
            Image(systemName: listening ? "mic.fill" : "mic")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(listening ? BlackoutDS.Red.hot : BlackoutDS.Surface.void)
                .frame(width: BlackoutDS.Hit.sm, height: BlackoutDS.Hit.sm)
                .background(BlackoutDS.Silver.metal)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(denied || !enabled ? BlackoutDS.Comms.dimmed : 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled && !denied)
        .accessibilityLabel(ConvenienceCopy.dictation)
        .onDisappear { stop() }
    }

    private func toggle() {
        if listening {
            stop()
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                switch status {
                case .authorized:
                    denied = false
                    start()
                case .denied, .restricted:
                    denied = true
                    onDenied()
                default:
                    denied = true
                    onDenied()
                }
            }
        }
    }

    private func start() {
        stop()
        prefix = text
        let speech = SFSpeechRecognizer(locale: Locale.current)
        recognizer = speech
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        request = req
        let next = AVAudioEngine()
        let input = next.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            denied = true
            stop()
            onDenied()
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            next.prepare()
            try next.start()
            engine = next
        } catch {
            denied = true
            stop()
            onDenied()
            return
        }
        listening = true
        task = speech?.recognitionTask(with: req) { result, _ in
            Task { @MainActor in
                if let result {
                    let spoken = result.bestTranscription.formattedString
                    if prefix.isEmpty {
                        text = spoken
                    } else {
                        text = prefix + (prefix.hasSuffix(" ") ? "" : " ") + spoken
                    }
                    if result.isFinal {
                        stop()
                    }
                }
            }
        }
    }

    private func stop() {
        listening = false
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
