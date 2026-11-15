import AVFoundation
import Speech

/// 口令匹配。纯函数，便于测试。
enum VoicePhraseMatcher {
    /// 否定或拖延的说法（「还没到」「不行」「等一下」）不算确认。
    static let negations = ["没", "不", "别", "等"]

    static func matches(_ transcript: String, phrases: [String]) -> Bool {
        let text = transcript.replacingOccurrences(of: " ", with: "")
        guard !negations.contains(where: { text.contains($0) }) else { return false }
        return phrases.contains(where: { text.contains($0) })
    }
}

/// 手忙时的语音确认：用户显式点一下，收听几秒，只用设备本地识别。
/// 不支持本地识别、权限被拒或被系统打断时直接停下，按钮入口始终可用。
@MainActor
final class VoiceConfirmer: ObservableObject {
    enum Availability: Equatable {
        case unknown
        case available
        /// 当前设备或语言不支持本地识别。
        case unsupported
        case denied
    }

    @Published private(set) var isListening = false
    @Published private(set) var availability: Availability = .unknown

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var generation = 0

    var supportsOnDevice: Bool {
        guard let recognizer else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    func refreshAvailability() {
        guard supportsOnDevice else { availability = .unsupported; return }
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVAudioApplication.shared.recordPermission
        if speech == .denied || speech == .restricted || mic == .denied {
            availability = .denied
        } else if speech == .authorized, mic == .granted {
            availability = .available
        } else {
            availability = .unknown
        }
    }

    /// 用户打开「语音确认」开关时才申请权限。
    func requestPermissions() async -> Bool {
        guard supportsOnDevice else { availability = .unsupported; return false }
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        var micOK = false
        if speechOK {
            micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        availability = (speechOK && micOK) ? .available : .denied
        return speechOK && micOK
    }

    func listen(phrases: [String], window: TimeInterval = 8, onMatch: @escaping () -> Void) {
        stop()
        guard availability == .available, let recognizer, recognizer.isAvailable, !phrases.isEmpty else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        do {
            try AudioSessionCoordinator.useRecording()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else { throw CocoaError(.featureUnsupported) }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            teardown()
            return
        }

        generation += 1
        let current = generation
        self.request = request
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let ended = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self, self.generation == current, self.isListening else { return }
                if let transcript, VoicePhraseMatcher.matches(transcript, phrases: phrases) {
                    self.stop()
                    onMatch()
                } else if ended {
                    self.stop()
                }
            }
        }

        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stopIfCurrent(current)
        }
    }

    private func stopIfCurrent(_ value: Int) {
        if generation == value { stop() }
    }

    func stop() {
        guard isListening || task != nil else { return }
        generation += 1
        teardown()
    }

    private func teardown() {
        timeout?.cancel()
        timeout = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        isListening = false
        AudioSessionCoordinator.release()
    }
}
