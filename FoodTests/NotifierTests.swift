import UserNotifications
import XCTest
@testable import Food

final class NotifierTests: XCTestCase {
    func testForegroundAlertIsSilentOnlyWhileCookingScreenHandlesIt() {
        XCTAssertEqual(UserNotificationTimerNotifier.foregroundPresentation(appHandlesAlerts: true), [])
        let home = UserNotificationTimerNotifier.foregroundPresentation(appHandlesAlerts: false)
        XCTAssertTrue(home.contains(.banner), "焖煮中回到首页，到点也要弹出")
        XCTAssertTrue(home.contains(.sound))
    }

    func testHomeResumeTitleShowsBraiseCountdownAndExpiry() throws {
        let recipe = try RecipeStore.loadBundled()
        let engine = SessionEngine(recipe: recipe, timerOverride: .init(seconds: 90, extendSeconds: 10))
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var (session, _) = engine.start(now: t0)
        XCTAssertEqual(HomeView.resumeTitle(recipe, session, now: t0), "继续做菜 · 备料")

        while let step = engine.step(of: session), step.timer == nil {
            _ = engine.confirm(&session, stepID: step.id, now: t0)
        }
        XCTAssertEqual(HomeView.resumeTitle(recipe, session, now: t0.addingTimeInterval(5)), "继续做菜 · 焖煮 · 剩 01:25")
        XCTAssertEqual(HomeView.resumeTitle(recipe, session, now: t0.addingTimeInterval(95)), "继续做菜 · 焖煮 · 该开盖检查了",
                       "到点但还没 tick（App 刚回前台）也要显示该检查")
        _ = engine.tick(&session, now: t0.addingTimeInterval(95))
        XCTAssertEqual(HomeView.resumeTitle(recipe, session, now: t0.addingTimeInterval(96)), "继续做菜 · 焖煮 · 该开盖检查了")
    }
}
