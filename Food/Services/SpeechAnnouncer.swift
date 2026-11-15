import AVFoundation

/// 普通话短句播报。新的一句会打断上一句，保证听到的总是最新状态。
final class SpeechAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "zh-CN")

    var isMuted = false {
        didSet { if isMuted { stop() } }
    }
    /// 开始出声前回调（主线程），用来停止语音收听。
    var onWillSpeak: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        guard !isMuted, !text.isEmpty else { return }
        onWillSpeak?()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        AudioSessionCoordinator.usePlayback()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// 说完后释放音频会话，让被压低的音乐恢复音量。
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            if !synthesizer.isSpeaking { AudioSessionCoordinator.release() }
        }
    }
}

enum AudioSessionCoordinator {
    /// 播报：不受静音拨片影响，和用户正在放的音乐混音并压低对方。
    static func usePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
    }

    static func useRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true)
    }

    static func release() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
