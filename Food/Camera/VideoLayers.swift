import AVFoundation
import SwiftUI
import UIKit

/// 相机预览。画面不加滤镜、不盖材质，保持原始色彩。
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

/// AVPlayer 画面，用于示范短片和 Simulator 样本。
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = gravity
    }
}

/// 提示视频的播放状态：默认静音，可重播、暂停、定格目标帧。
@MainActor
final class HintPlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var isPlaying = false
    @Published private(set) var isFrozenOnTarget = false
    @Published private(set) var loadedStepID: String?
    @Published private(set) var isMissing = false

    private var endObserver: NSObjectProtocol?

    init() {
        player.isMuted = true
        player.actionAtItemEnd = .pause
    }

    func load(step: RecipeStep, autoplay: Bool = true) {
        guard loadedStepID != step.id else { return }
        loadedStepID = step.id
        isFrozenOnTarget = false
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        guard let url = RecipeStore.mediaURL(step.demo.video) else {
            player.replaceCurrentItem(with: nil)
            isMissing = true
            isPlaying = false
            return
        }
        isMissing = false
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isPlaying = false }
        }
        if autoplay { play() } else { isPlaying = false }
    }

    func play() {
        isFrozenOnTarget = false
        if let item = player.currentItem, item.currentTime() >= item.duration, item.duration.isNumeric {
            player.seek(to: .zero)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func replay() {
        isFrozenOnTarget = false
        player.seek(to: .zero)
        player.play()
        isPlaying = true
    }

    /// 定格到目标帧，方便和下方锅面对比。
    func freeze(at seconds: Double) {
        player.pause()
        isPlaying = false
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        isFrozenOnTarget = true
    }
}
