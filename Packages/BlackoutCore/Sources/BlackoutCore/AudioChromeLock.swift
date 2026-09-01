import Foundation

/// Crisis 51: audio 10/10. On-device only. SOS speak stays off chrome.
public enum AudioChromeLock {
    public static let walkSpeakButton = true
    public static let lockVoiceWhileLocked = true
    public static let lockVoiceInterval: TimeInterval = 2.2
    public static let speechRateMin: Float = 0.47
    public static let speechRateMax: Float = 0.52
    public static let interruptible = true
    public static let restartsTimerOnRender = false
    /// SPEAK while LOCK on + target uses lock phrase, not street TBT.
    public static let speakPrefersLockWhenLocked = true
    public static let fieldAskMic = true
    public static let fieldAskMicDenyFallsBackToType = true
    public static let fieldAskSpokenStep = true
    public static let fieldAskUsesWAN = false
    public static let pttOnComms = true
    public static let pttOnMap = false
    public static let sosSpeakOnChrome = false
    public static let cloudTTS = false
    /// First-open Map constructs NavigateSession + CompassLockSession.
    /// AVSpeechSynthesizer / AVAudioEngine stay off that init. SOS already lazy.
    public static let constructsSynthesizerOnInit = false
    public static let constructsAudioEngineOnViewInit = false
    public static let installsPTTRemoteOnAppInit = false

    public static func speakUsesLockPhrase(isLocked: Bool, hasTarget: Bool) -> Bool {
        speakPrefersLockWhenLocked && isLocked && hasTarget
    }

    public static func clampedLockRate(_ rate: Float) -> Float {
        min(speechRateMax, max(speechRateMin, rate))
    }
}
