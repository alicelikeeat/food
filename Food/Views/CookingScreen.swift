import SwiftUI
import UIKit

/// 做菜流程容器：按会话状态在双视频页、焖煮状态和完成页之间切换。
struct CookingScreen: View {
    @StateObject private var vm: CookingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false
    @State private var showExit = false

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(recipe: Recipe, resume: CookingSession?, env: AppEnvironment) {
        // StateObject 的 wrappedValue 是 autoclosure，只在首次出现时创建一次。
        _vm = StateObject(wrappedValue: CookingViewModel(
            recipe: recipe, resume: resume, store: env.store, notes: env.notes, notifier: env.notifier
        ))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("退出", systemImage: "xmark") {
                            if vm.session.isFinished {
                                vm.finish(note: vm.savedNote)
                                dismiss()
                            } else {
                                showExit = true
                            }
                        }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(vm.isMuted ? "打开播报" : "静音播报",
                               systemImage: vm.isMuted ? "speaker.slash" : "speaker.wave.2") {
                            vm.isMuted.toggle()
                        }
                        Button("设置", systemImage: "slider.horizontal.3") {
                            showSettings = true
                        }
                    }
                }
        }
        .onAppear { vm.appeared() }
        .onDisappear { vm.leave() }
        .onReceive(ticker) { vm.tick(now: $0) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            vm.sceneChanged(active: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            vm.sceneChanged(active: false)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(vm: vm, voice: vm.voice)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("要退出做菜吗？", isPresented: $showExit, titleVisibility: .visible) {
            Button("稍后继续") { dismiss() }
            Button("放弃这次", role: .destructive) {
                vm.abandon()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("稍后继续会保留进度和计时。")
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.session.isFinished {
            DoneView(vm: vm) { dismiss() }
        } else if let step = vm.currentStep {
            if step.timer != nil {
                BraiseView(vm: vm, hint: vm.hint, step: step)
            } else {
                DualVideoView(vm: vm, hint: vm.hint, voice: vm.voice, step: step)
            }
        }
    }

    private var title: String {
        guard let step = vm.currentStep else { return "完成" }
        return "\(vm.session.stepIndex + 1)/\(vm.stepCount) \(step.title)"
    }
}

struct SettingsSheet: View {
    @ObservedObject var vm: CookingViewModel
    @ObservedObject var voice: VoiceConfirmer
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.shortTimers) private var shortTimers = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("静音播报", isOn: $vm.isMuted)
                } footer: {
                    Text("静音后所有提示仍以文字显示。")
                }
                Section {
                    Toggle("语音确认", isOn: Binding(
                        get: { vm.voiceConfirmEnabled },
                        set: { vm.setVoiceConfirm($0) }
                    ))
                    .disabled(voice.availability == .unsupported)
                } footer: {
                    Text(voiceFooter)
                }
                Section {
                    Toggle("关闭相机", isOn: $vm.cameraOff)
                } footer: {
                    Text("关闭后示范、确认和计时照常可用。相机画面只在内存中处理，不保存、不上传。")
                }
                #if DEBUG
                Section {
                    Toggle("短测试计时（20 秒 / 延长 10 秒）", isOn: $shortTimers)
                } footer: {
                    Text("仅调试构建可见。下次开始做菜时生效。")
                }
                #endif
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { voice.refreshAvailability() }
        }
    }

    private var voiceFooter: String {
        switch voice.availability {
        case .unsupported:
            return "这台设备不支持普通话本地识别，请用按钮确认。"
        case .denied:
            return "麦克风或语音识别权限未开启，可在系统设置中打开。按钮确认始终可用。"
        case .available, .unknown:
            return "开启后，主按钮旁会出现麦克风。点一下收听约 8 秒，说出按钮上的话即可确认。只使用设备本地识别。"
        }
    }
}
