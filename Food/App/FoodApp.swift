import SwiftUI

@main
struct FoodApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(env)
        }
    }
}

/// App 级依赖。通知代理在启动时就位，冷启动恢复时也能正确处理前台到期。
@MainActor
final class AppEnvironment: ObservableObject {
    let recipe: Recipe?
    let store = SessionStore()
    let notes = NoteStore()
    let notifier: TimerNotifying = UserNotificationTimerNotifier()

    @Published private(set) var unfinished: CookingSession?
    @Published private(set) var lastNote: String?

    init() {
        recipe = try? RecipeStore.loadBundled()
        refresh()
    }

    func refresh() {
        guard let recipe else { return }
        unfinished = store.loadUnfinished(recipeID: recipe.id)
        lastNote = notes.note(for: recipe.id)
    }

    /// 「重新开始」前丢弃旧会话，并移除它的计时提醒。
    func discardUnfinished() {
        if let id = unfinished?.timerID { notifier.cancel(id: id) }
        store.clear()
        refresh()
    }
}
