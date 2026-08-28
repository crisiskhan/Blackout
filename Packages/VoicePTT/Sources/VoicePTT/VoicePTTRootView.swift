import AVFoundation
import BlackoutCore
import DesignSystem
import SwiftUI

public struct VoicePTTRootView: View {
    let persistence: any PersistenceServing
    var extremeSaver: Bool

    @State private var recorder: AVAudioRecorder?
    @State private var player: AVAudioPlayer?
    @State private var clips: [VoiceClipRecordDTO] = []
    @State private var isRecording = false
    @State private var denied = false
    @State private var error: String?

    public init(persistence: any PersistenceServing, extremeSaver: Bool) {
        self.persistence = persistence
        self.extremeSaver = extremeSaver
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader("Voice PTT", subtitle: "Local record and playback. Live PTT-over-mesh is wave 2.")
            if extremeSaver {
                Text("Extreme Saver paused recording. SOS is unaffected.")
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Semantic.warn)
            }
            if denied {
                PermissionDenied(
                    kind: .microphone,
                    reason: "Microphone denied. Text comms and SOS still work."
                )
            }
            MetalButton(isRecording ? "Stop" : "Hold record (tap to start)", height: BlackoutDS.Hit.lg) {
                Task { await toggleRecord() }
            }
            .disabled(extremeSaver)
            if let error {
                Text(error)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Semantic.warn)
            }
            ForEach(clips) { clip in
                HStack {
                    VStack(alignment: .leading) {
                        Text(clip.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(BlackoutDS.Silver.bright)
                        Text(String(format: "%.1f s", clip.durationSeconds))
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.dim)
                    }
                    Spacer()
                    GhostButton("Play", height: BlackoutDS.Hit.sm) {
                        play(clip)
                    }
                    .frame(width: 120)
                }
            }
            Spacer()
        }
        .padding(20)
        .padding(.bottom, 80)
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .task { clips = (try? persistence.voiceClips()) ?? [] }
    }

    private func toggleRecord() async {
        if isRecording {
            recorder?.stop()
            isRecording = false
            if let url = recorder?.url {
                persist(url: url)
            }
            recorder = nil
            return
        }
        let granted = await requestMic()
        guard granted else {
            denied = true
            return
        }
        denied = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ptt-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.record()
            recorder = rec
            isRecording = true
        } catch {
            self.error = "Recorder unavailable."
        }
    }

    private func requestMic() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }

    private func persist(url: URL) {
        let duration = playerDuration(url) 
        let dto = VoiceClipRecordDTO(fileName: url.lastPathComponent, durationSeconds: duration)
        try? persistence.saveVoiceClip(dto)
        clips = (try? persistence.voiceClips()) ?? []
    }

    private func playerDuration(_ url: URL) -> Double {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }

    private func play(_ clip: VoiceClipRecordDTO) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(clip.fileName)
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            self.error = "Clip missing on disk."
        }
    }
}
