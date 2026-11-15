import SwiftUI

/// 焖煮状态：时间占主视觉，两路视频收成可展开的入口。相机与分析默认停用，展开时才恢复。
struct BraiseView: View {
    @ObservedObject var vm: CookingViewModel
    @ObservedObject var hint: HintPlayerModel
    let step: RecipeStep

    private var isWaitingCheck: Bool { vm.session.phase == .awaitingCheck }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                clock
                    .padding(.top, 24)

                Text(step.instruction)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let timer = step.timer, !timer.verified {
                    Text("默认时长尚待试菜核定，请以开盖检查为准。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        expandButton("查看示范", icon: "play.rectangle", isOn: $vm.braiseShowsDemo)
                        expandButton("打开锅面", icon: "camera", isOn: $vm.braiseShowsPot)
                    }
                }

                if vm.braiseShowsDemo {
                    HintVideoSurface(hint: hint)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                if vm.braiseShowsPot {
                    PotFeedSurface(vm: vm)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) { actions }
    }

    private var clock: some View {
        VStack(spacing: 6) {
            Text(isWaitingCheck ? "待检查" : "焖煮中")
                .font(.headline)
                .foregroundStyle(.secondary)
            if isWaitingCheck {
                Text("开盖检查")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(step.timer?.checkPrompt ?? "")
                    .font(.title3)
                    .multilineTextAlignment(.center)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = vm.session.remaining(now: context.date)
                    Text(Self.clockString(remaining))
                        .font(.system(size: 88, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel("剩余 \(Self.spokenRemaining(remaining))")
                }
                if let deadline = vm.session.timerDeadline {
                    Text("预计 \(deadline.formatted(date: .omitted, time: .shortened)) 到点")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func expandButton(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation { isOn.wrappedValue.toggle() }
        } label: {
            Label(isOn.wrappedValue ? "收起" + String(title.suffix(2)) : title,
                  systemImage: isOn.wrappedValue ? "chevron.up" : icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if isWaitingCheck {
                    Button {
                        vm.proceedAfterCheck()
                    } label: {
                        Text("进入\(vm.nextStepTitle.map { String($0.prefix(2)) } ?? "下一步")")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        vm.extendBraise()
                    } label: {
                        Text(vm.extendLabel).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                } else {
                    Button {
                        vm.checkEarly()
                    } label: {
                        Text("提前开盖检查").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    static func clockString(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func spokenRemaining(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        let minutes = total / 60, seconds = total % 60
        if minutes == 0 { return "\(seconds) 秒" }
        return seconds == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(seconds) 秒"
    }
}

/// 完成页：显示完成状态，保存一句做法备注。
struct DoneView: View {
    @ObservedObject var vm: CookingViewModel
    let onClose: () -> Void
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                    .padding(.top, 32)
                Text("\(vm.recipe.name)做好了")
                    .font(.largeTitle.bold())
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    Text("做法备注")
                        .font(.headline)
                    TextField("一句话，例如：下次糖色再早半分钟下肉", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .focused($noteFocused)
                    Text("下次打开\(vm.recipe.name)时会显示在首页。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                noteFocused = false
                vm.finish(note: note)
                onClose()
            } label: {
                Text("保存并完成")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear { note = vm.savedNote }
    }

    private var summary: String {
        let session = vm.session
        var parts: [String] = []
        if let end = session.finishedAt {
            let minutes = max(1, Int(end.timeIntervalSince(session.startedAt) / 60))
            parts.append("用时约 \(minutes) 分钟")
        }
        parts.append("手动确认 \(session.confirmCount) 次")
        if session.extendCount > 0 { parts.append("延长焖煮 \(session.extendCount) 次") }
        return parts.joined(separator: " · ")
    }
}
