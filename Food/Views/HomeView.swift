import SwiftUI

struct CookingLaunch: Identifiable {
    let id = UUID()
    let resume: CookingSession?
}

struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var launch: CookingLaunch?
    @State private var confirmRestart = false

    var body: some View {
        NavigationStack {
            if let recipe = env.recipe {
                recipeList(recipe)
                    .navigationTitle(recipe.name)
                    .safeAreaInset(edge: .bottom) { actions(recipe) }
                    .fullScreenCover(item: $launch, onDismiss: { env.refresh() }) { launch in
                        CookingScreen(recipe: recipe, resume: launch.resume, env: env)
                    }
                    .onAppear { env.refresh() }
            } else {
                ContentUnavailableView("菜谱加载失败", systemImage: "exclamationmark.triangle",
                                       description: Text("随包菜谱文件缺失或格式不正确。"))
            }
        }
    }

    private func recipeList(_ recipe: Recipe) -> some View {
        List {
            Section {
                Text(recipe.summary)
                LabeledContent("默认份量", value: recipe.servings)
            }
            if let note = env.lastNote {
                Section("上次备注") {
                    Label(note, systemImage: "note.text")
                }
            }
            Section("食材") {
                ForEach(recipe.ingredients) { item in
                    LabeledContent(item.name, value: item.amount)
                }
            }
            Section("器具") {
                ForEach(recipe.cookware, id: \.self) { Text($0) }
            }
            Section("步骤预览") {
                ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(.headline)
                            if let timer = step.timer {
                                Text("计时约 \(SessionEngine.buttonDuration(timer.seconds))" + (timer.verified ? "" : "（待试菜核定）"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else if step.observation != nil {
                                Text("对照示范看锅面颜色")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ recipe: Recipe) -> some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 10) {
                if let unfinished = env.unfinished {
                    Button {
                        launch = CookingLaunch(resume: unfinished)
                    } label: {
                        Text(resumeTitle(recipe, unfinished)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        confirmRestart = true
                    } label: {
                        Text("重新开始").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                } else {
                    Button {
                        launch = CookingLaunch(resume: nil)
                    } label: {
                        Text("开始做菜").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .confirmationDialog("放弃未完成的这次，重新开始？", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("重新开始", role: .destructive) {
                env.discardUnfinished()
                launch = CookingLaunch(resume: nil)
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func resumeTitle(_ recipe: Recipe, _ session: CookingSession) -> String {
        guard recipe.steps.indices.contains(session.stepIndex) else { return "继续做菜" }
        return "继续做菜 · \(recipe.steps[session.stepIndex].title)"
    }
}
