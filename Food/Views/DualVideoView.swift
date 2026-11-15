import SwiftUI
import UIKit

/// 做菜页：上方提示视频，下方观察视频，底部固定一句指令和一个主按钮。
/// 玻璃只用在视频外缘的控件上，两路画面本身不盖任何材质。
struct DualVideoView: View {
    @ObservedObject var vm: CookingViewModel
    @ObservedObject var hint: HintPlayerModel
    @ObservedObject var voice: VoiceConfirmer
    let step: RecipeStep

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 8) {
                VideoPanel(title: "提示视频", tag: step.demo.isPlaceholder ? "占位素材" : nil) {
                    HintVideoSurface(hint: hint)
                } controls: {
                    HintControls(hint: hint, targetSeconds: step.demo.targetFrameSeconds)
                }

                if let target = step.observation {
                    SwatchStrip(target: target, reading: vm.feedStatus == .running ? vm.reading : nil)
                }

                VideoPanel(title: "观察视频", tag: PotFeedSurface.sourceTag) {
                    PotFeedSurface(vm: vm)
                } controls: {
                    PotStatus(vm: vm)
                }

                InstructionBar(vm: vm, voice: voice, step: step)
                    .frame(maxHeight: geo.size.height * 0.42)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

struct VideoPanel<Content: View, Controls: View>: View {
    let title: String
    let tag: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        VStack(spacing: 6) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 96)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
            HStack(spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                if let tag {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().stroke(.secondary.opacity(0.5)))
                }
                Spacer(minLength: 4)
                controls()
            }
        }
    }
}

struct HintVideoSurface: View {
    @ObservedObject var hint: HintPlayerModel

    var body: some View {
        if hint.isMissing {
            Label("示范素材缺失，请按文字指令操作", systemImage: "film")
                .font(.callout)
                .foregroundStyle(.white)
                .padding()
        } else {
            PlayerLayerView(player: hint.player)
                .accessibilityLabel("当前步骤示范，静音播放")
        }
    }
}

struct HintControls: View {
    @ObservedObject var hint: HintPlayerModel
    let targetSeconds: Double?

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if let targetSeconds {
                    Button {
                        hint.freeze(at: targetSeconds)
                    } label: {
                        Label(hint.isFrozenOnTarget ? "已定格目标" : "定格目标", systemImage: "scope")
                    }
                    .accessibilityHint("把示范停在目标颜色那一帧，方便和锅面对比")
                }
                Button("重播", systemImage: "arrow.counterclockwise") { hint.replay() }
                    .labelStyle(.iconOnly)
                Button(hint.isPlaying ? "暂停" : "播放", systemImage: hint.isPlaying ? "pause.fill" : "play.fill") {
                    hint.togglePlay()
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }
}

/// 三种糖色参考。当前观测结果用文字和勾选标出，颜色只是辅助。
struct SwatchStrip: View {
    let target: ObservationTarget
    let reading: CaramelReading?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(target.references) { swatch in
                let isCurrent = reading?.rawValue == swatch.id
                HStack(spacing: 6) {
                    swatchImage(swatch.image)
                        .frame(width: 34, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.secondary.opacity(0.4)))
                        .accessibilityHidden(true)
                    Text(swatch.label)
                        .font(.caption.weight(isCurrent ? .bold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("参考：\(swatch.label)" + (isCurrent ? "，锅面当前接近这一档" : ""))
            }
        }
    }

    @ViewBuilder
    private func swatchImage(_ name: String) -> some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image).resizable()
        } else {
            Color.secondary.opacity(0.3)
        }
    }
}

/// 观察视频：真机为后置相机预览，Simulator 为明确标记的合成样本。
struct PotFeedSurface: View {
    @ObservedObject var vm: CookingViewModel

    static var sourceTag: String? {
        #if targetEnvironment(simulator)
        return "合成样本"
        #else
        return nil
        #endif
    }

    var body: some View {
        if vm.cameraOff {
            notice("相机已关闭。请对照上方示范。", button: "打开相机") { vm.cameraOff = false }
        } else {
            switch vm.feedStatus {
            case .denied:
                notice("未获得相机权限。示范、确认和计时照常可用。", button: "去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            case .unavailable:
                notice("相机暂时不可用。请对照上方示范。", button: nil) {}
            case .interrupted:
                notice("相机被系统占用，结束后会自动恢复。", button: nil) {}
            case .idle, .running:
                live
            }
        }
    }

    @ViewBuilder
    private var live: some View {
        if let camera = vm.feed as? CameraController {
            CameraPreview(session: camera.session)
                .accessibilityLabel("后置相机拍到的锅面")
        } else if let sample = vm.feed as? SampleFeedController {
            PlayerLayerView(player: sample.player, gravity: .resizeAspectFill)
                .accessibilityLabel("合成样本画面，不是相机")
        }
    }

    private func notice(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if let button {
                Button(button, action: action)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding()
    }
}

/// 观察区的一句状态。文字本身说明状态，图标和颜色只做辅助。
struct PotStatus: View {
    @ObservedObject var vm: CookingViewModel

    var body: some View {
        if let hint = vm.observationHint {
            Label(hint, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)
                .accessibilityLabel("锅面观察：\(hint)")
        }
    }

    private var icon: String {
        guard vm.feedStatus == .running else { return "eye" }
        switch vm.reading {
        case .tooPale: return "sun.max"
        case .nearTarget: return "checkmark.circle"
        case .maybeDark: return "exclamationmark.triangle"
        case .unclear, .none: return "eye"
        }
    }
}

struct InstructionBar: View {
    @ObservedObject var vm: CookingViewModel
    @ObservedObject var voice: VoiceConfirmer
    let step: RecipeStep

    var body: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .vertical) {
                instruction
                ScrollView { instruction }
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("再说一遍", systemImage: "speaker.wave.2") { vm.repeatInstruction() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .disabled(vm.isMuted)

                    if vm.voiceButtonVisible {
                        Button(voice.isListening ? "正在听，点按停止" : "语音确认",
                               systemImage: voice.isListening ? "waveform" : "mic") {
                            if voice.isListening { voice.stop() } else { vm.startVoiceConfirm() }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                    }

                    if let label = step.confirmLabel {
                        Button {
                            vm.confirm(stepID: step.id)
                        } label: {
                            Text(label)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .controlSize(.large)
            }
            if voice.isListening {
                Text("正在听…说「\(step.confirmPhrases.first ?? "")」")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var instruction: some View {
        Text(step.instruction)
            .font(.title3.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}
