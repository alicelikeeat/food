import AVFoundation
import Foundation

enum FeedStatus: Equatable {
    case idle
    case running
    case denied
    case unavailable
    case interrupted
}

/// 锅面画面来源。真机是后置相机，Simulator 是明确标记的合成样本。
protocol PotFeed: AnyObject {
    /// 分析结果回调，在后台队列触发。
    var onStats: ((FrameStats) -> Void)? { get set }
    /// 状态回调，在主线程触发。
    var onStatus: ((FeedStatus) -> Void)? { get set }
    func start()
    func stop()
    func setAnalysis(enabled: Bool)
}

/// 线程安全的采样闸门：分析开关 + 最小采样间隔（默认每秒 2 帧）。
final class AnalysisGate {
    private let lock = NSLock()
    private var enabled = false
    private var lastSample = -Double.infinity
    private let minInterval: Double

    init(framesPerSecond: Double = 2) {
        minInterval = 1 / framesPerSecond
    }

    func setEnabled(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        enabled = value
        lastSample = -Double.infinity
    }

    /// `time` 为帧的呈现时间（秒）。间隔不够的帧直接跳过。
    func shouldSample(at time: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return false }
        // 时间回退（样本循环播放）时重新开始计。
        if time < lastSample { lastSample = -Double.infinity }
        guard time - lastSample >= minInterval else { return false }
        lastSample = time
        return true
    }
}

/// 后置相机：一套捕获会话，同时给预览层和低频分析输出供帧。
final class CameraController: NSObject, PotFeed, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onStats: ((FrameStats) -> Void)?
    var onStatus: ((FeedStatus) -> Void)?

    private let sessionQueue = DispatchQueue(label: "food.camera.session")
    private let analysisQueue = DispatchQueue(label: "food.camera.analysis", qos: .utility)
    private let output = AVCaptureVideoDataOutput()
    private let gate = AnalysisGate()
    // 以下只在 sessionQueue 上读写。
    private var configured = false
    private var wantsRunning = false
    private var analysisEnabled = false

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(wasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        center.addObserver(self, selector: #selector(interruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
        center.addObserver(self, selector: #selector(runtimeError), name: .AVCaptureSessionRuntimeError, object: session)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startAuthorized()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.startAuthorized() } else { self?.report(.denied) }
            }
        default:
            report(.denied)
        }
    }

    /// 可重复调用：会话已在运行时什么都不做，不会产生第二套会话。
    private func startAuthorized() {
        sessionQueue.async { [self] in
            wantsRunning = true
            if !configured {
                guard configure() else { report(.unavailable); return }
                configured = true
            }
            applyAnalysisConnection()
            if !session.isRunning { session.startRunning() }
            report(session.isRunning ? .running : .unavailable)
        }
    }

    /// 离开页面或进入后台时调用，释放相机。
    func stop() {
        sessionQueue.async { [self] in
            wantsRunning = false
            if session.isRunning { session.stopRunning() }
            report(.idle)
        }
    }

    func setAnalysis(enabled: Bool) {
        gate.setEnabled(enabled)
        sessionQueue.async { [self] in
            analysisEnabled = enabled
            applyAnalysisConnection()
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard session.canAddInput(input) else { return false }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // 分析跟不上时丢掉积压帧，预览不受影响。
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: analysisQueue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        return true
    }

    /// 不在糖色步骤时直接断开分析输出的连接，连回调都不再产生。
    private func applyAnalysisConnection() {
        output.connection(with: .video)?.isEnabled = analysisEnabled
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard gate.shouldSample(at: time),
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let stats = FrameSampler.stats(from: buffer) else { return }
        onStats?(stats)
    }

    private func report(_ status: FeedStatus) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(status) }
    }

    @objc private func wasInterrupted(_ note: Notification) {
        report(.interrupted)
    }

    @objc private func interruptionEnded(_ note: Notification) {
        sessionQueue.async { [self] in
            guard wantsRunning else { return }
            if !session.isRunning { session.startRunning() }
            report(session.isRunning ? .running : .unavailable)
        }
    }

    @objc private func runtimeError(_ note: Notification) {
        sessionQueue.async { [self] in
            guard wantsRunning else { return }
            if !session.isRunning { session.startRunning() }
            report(session.isRunning ? .running : .unavailable)
        }
    }
}

/// Simulator 用：循环播放合成样本，并以同样的 2 fps 闸门取帧分析。
final class SampleFeedController: NSObject, PotFeed {
    let player = AVPlayer()
    var onStats: ((FrameStats) -> Void)?
    var onStatus: ((FeedStatus) -> Void)?

    private let gate = AnalysisGate()
    private let analysisQueue = DispatchQueue(label: "food.sample.analysis", qos: .utility)
    private var videoOutput: AVPlayerItemVideoOutput?
    private var timer: Timer?
    private var endObserver: NSObjectProtocol?

    static let fileName = "sample_pot_caramel.mp4"

    func start() {
        if player.currentItem == nil {
            guard let url = RecipeStore.mediaURL(Self.fileName) else { onStatus?(.unavailable); return }
            let item = AVPlayerItem(url: url)
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            item.add(output)
            videoOutput = output
            player.replaceCurrentItem(with: item)
            player.isMuted = true
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                self?.player.seek(to: .zero)
                self?.player.play()
            }
        }
        player.play()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.pull() }
        }
        onStatus?(.running)
    }

    func stop() {
        player.pause()
        timer?.invalidate()
        timer = nil
        onStatus?(.idle)
    }

    func setAnalysis(enabled: Bool) {
        gate.setEnabled(enabled)
    }

    private func pull() {
        guard let output = videoOutput, let item = player.currentItem else { return }
        let time = item.currentTime()
        guard gate.shouldSample(at: time.seconds),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        analysisQueue.async { [weak self] in
            guard let stats = FrameSampler.stats(from: buffer) else { return }
            self?.onStats?(stats)
        }
    }

    deinit {
        timer?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}
