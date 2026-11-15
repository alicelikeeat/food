import XCTest
@testable import Food

final class SessionEngineTests: XCTestCase {
    private var recipe: Recipe!
    private var engine: SessionEngine!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        recipe = try RecipeStore.loadBundled()
        engine = SessionEngine(recipe: recipe, timerOverride: .init(seconds: 20, extendSeconds: 10))
    }

    /// 依次确认到指定步骤为止（不含该步骤）。
    private func makeSession(at stepID: String) -> CookingSession {
        var (session, _) = engine.start(now: t0)
        while let step = engine.step(of: session), step.id != stepID {
            _ = engine.confirm(&session, stepID: step.id, now: t0)
        }
        return session
    }

    private func scheduled(_ effects: [SessionEffect]) -> [(id: String, deadline: Date)] {
        effects.compactMap {
            if case .scheduleTimer(let id, let deadline, _) = $0 { return (id, deadline) }
            return nil
        }
    }

    // MARK: 菜谱

    func testBundledRecipeIsWellFormed() {
        XCTAssertEqual(recipe.id, "hongshaorou")
        XCTAssertEqual(recipe.steps.map(\.id), ["prep", "blanch", "caramel", "sear", "braise", "reduce"])
        XCTAssertEqual(Set(recipe.steps.map(\.id)).count, recipe.steps.count, "步骤 ID 必须唯一")
        for step in recipe.steps {
            XCTAssertNotNil(RecipeStore.mediaURL(step.demo.video), "缺示范素材 \(step.demo.video)")
            // 每一步要么靠用户确认推进，要么是计时步骤。
            XCTAssertTrue((step.confirmLabel != nil) != (step.timer != nil), step.id)
        }
        XCTAssertNotNil(recipe.steps[2].observation)
        XCTAssertEqual(recipe.steps[3].confirmLabel, "已加盖")
    }

    // MARK: 步骤推进

    func testStartWaitsOnFirstStepWithoutTimer() {
        let (session, effects) = engine.start(now: t0)
        XCTAssertEqual(session.stepIndex, 0)
        XCTAssertEqual(session.phase, .awaitingConfirm)
        XCTAssertNil(session.timerDeadline)
        XCTAssertTrue(scheduled(effects).isEmpty)
    }

    func testConfirmAdvancesOneStep() {
        var (session, _) = engine.start(now: t0)
        _ = engine.confirm(&session, stepID: "prep", now: t0)
        XCTAssertEqual(engine.step(of: session)?.id, "blanch")
        XCTAssertEqual(session.confirmCount, 1)
    }

    func testDuplicateConfirmIsIgnored() {
        // 点按和语音几乎同时确认同一步：第二次带的是旧步骤 ID，必须被忽略。
        var (session, _) = engine.start(now: t0)
        let first = engine.confirm(&session, stepID: "prep", now: t0)
        let second = engine.confirm(&session, stepID: "prep", now: t0)
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(engine.step(of: session)?.id, "blanch")
        XCTAssertEqual(session.confirmCount, 1)
    }

    func testConfirmForWrongStepIsIgnored() {
        var (session, _) = engine.start(now: t0)
        XCTAssertTrue(engine.confirm(&session, stepID: "caramel", now: t0).isEmpty)
        XCTAssertEqual(session.stepIndex, 0)
    }

    func testConfirmCannotSkipRunningTimer() {
        var session = makeSession(at: "braise")
        XCTAssertTrue(engine.confirm(&session, stepID: "braise", now: t0).isEmpty)
        XCTAssertEqual(session.phase, .timerRunning)
    }

    // MARK: 计时

    func testNoTimerUntilLidConfirmed() {
        var session = makeSession(at: "sear")
        XCTAssertNil(session.timerDeadline)
        XCTAssertEqual(session.phase, .awaitingConfirm)

        let lidTime = t0.addingTimeInterval(600)
        let effects = engine.confirm(&session, stepID: "sear", now: lidTime)
        XCTAssertEqual(session.phase, .timerRunning)
        XCTAssertEqual(session.timerDeadline, lidTime.addingTimeInterval(20))
        let timers = scheduled(effects)
        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers.first?.id, "timer.hongshaorou.braise")
    }

    func testRecipeDurationUsedWithoutOverride() {
        let real = SessionEngine(recipe: recipe)
        var (session, _) = real.start(now: t0)
        for id in ["prep", "blanch", "caramel", "sear"] {
            _ = real.confirm(&session, stepID: id, now: t0)
        }
        XCTAssertEqual(session.timerDeadline, t0.addingTimeInterval(2400))
    }

    func testTickBeforeDeadlineDoesNothing() {
        var session = makeSession(at: "braise")
        XCTAssertTrue(engine.tick(&session, now: t0.addingTimeInterval(19)).isEmpty)
        XCTAssertEqual(session.phase, .timerRunning)
        XCTAssertEqual(session.remaining(now: t0.addingTimeInterval(5)), 15, accuracy: 0.001)
    }

    func testExpiryStopsAtAwaitingCheckAndAnnouncesOnce() {
        var session = makeSession(at: "braise")
        let first = engine.tick(&session, now: t0.addingTimeInterval(20.2))
        XCTAssertEqual(session.phase, .awaitingCheck)
        XCTAssertEqual(engine.step(of: session)?.id, "braise", "到点不能自动换步")
        XCTAssertEqual(first.filter { if case .speak = $0 { return true } else { return false } }.count, 1)
        XCTAssertTrue(first.contains(.cancelTimer(id: "timer.hongshaorou.braise")))

        // 之后无论再 tick 多少次，都不再产生任何提醒。
        XCTAssertTrue(engine.tick(&session, now: t0.addingTimeInterval(21)).isEmpty)
        XCTAssertTrue(engine.tick(&session, now: t0.addingTimeInterval(500)).isEmpty)
        XCTAssertEqual(session.phase, .awaitingCheck)
    }

    func testRestoreAfterKillRecomputesFromDeadline() throws {
        let running = makeSession(at: "braise")
        // 模拟杀进程：只剩磁盘上的 JSON。
        let data = try JSONEncoder().encode(running)
        var restored = try JSONDecoder().decode(CookingSession.self, from: data)
        XCTAssertEqual(restored, running)

        // 12 秒后重开：还在计时，剩余时间按截止时间重算。
        XCTAssertTrue(engine.tick(&restored, now: t0.addingTimeInterval(12)).isEmpty)
        XCTAssertEqual(restored.remaining(now: t0.addingTimeInterval(12)), 8, accuracy: 0.001)
    }

    func testRestoreAfterDeadlineShowsExpiredWithoutSpeakingAgain() throws {
        let running = makeSession(at: "braise")
        var restored = try JSONDecoder().decode(CookingSession.self, from: JSONEncoder().encode(running))
        // 到点 10 分钟后才回来：通知已经提醒过，App 只显示到期状态，不再播报。
        let effects = engine.tick(&restored, now: t0.addingTimeInterval(620))
        XCTAssertEqual(restored.phase, .awaitingCheck)
        XCTAssertEqual(effects, [.cancelTimer(id: "timer.hongshaorou.braise")])
    }

    func testExtendAfterExpiryReusesSameNotificationID() {
        var session = makeSession(at: "braise")
        _ = engine.tick(&session, now: t0.addingTimeInterval(20))
        let extendTime = t0.addingTimeInterval(45)
        let effects = engine.extend(&session, now: extendTime)

        XCTAssertEqual(session.phase, .timerRunning)
        XCTAssertEqual(session.timerDeadline, extendTime.addingTimeInterval(10))
        XCTAssertEqual(session.extendCount, 1)
        let timers = scheduled(effects)
        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers.first?.id, "timer.hongshaorou.braise", "延长必须更新原提醒，而不是新建一个")
        XCTAssertEqual(timers.first?.deadline, extendTime.addingTimeInterval(10))

        // 延长后再次到点，仍然停在待检查。
        _ = engine.tick(&session, now: extendTime.addingTimeInterval(10))
        XCTAssertEqual(session.phase, .awaitingCheck)
        XCTAssertEqual(engine.step(of: session)?.id, "braise")
    }

    func testExtendOnlyValidWhileAwaitingCheck() {
        var session = makeSession(at: "braise")
        XCTAssertTrue(engine.extend(&session, now: t0).isEmpty)
        XCTAssertEqual(session.extendCount, 0)
    }

    func testProceedAfterCheckCancelsTimerAndMovesOn() {
        var session = makeSession(at: "braise")
        _ = engine.tick(&session, now: t0.addingTimeInterval(20))
        let effects = engine.proceedAfterCheck(&session, now: t0.addingTimeInterval(30))
        XCTAssertEqual(engine.step(of: session)?.id, "reduce")
        XCTAssertNil(session.timerDeadline)
        XCTAssertNil(session.timerID)
        XCTAssertTrue(effects.contains(.cancelTimer(id: "timer.hongshaorou.braise")))
        // 重复点「进入收汁」不会再跳一步。
        XCTAssertTrue(engine.proceedAfterCheck(&session, now: t0.addingTimeInterval(31)).isEmpty)
        XCTAssertEqual(engine.step(of: session)?.id, "reduce")
    }

    func testCheckEarlyCancelsReminder() {
        var session = makeSession(at: "braise")
        let effects = engine.checkEarly(&session)
        XCTAssertEqual(session.phase, .awaitingCheck)
        XCTAssertEqual(effects, [.cancelTimer(id: "timer.hongshaorou.braise")])
        XCTAssertTrue(engine.tick(&session, now: t0.addingTimeInterval(100)).isEmpty)
    }

    func testAbandonRemovesReminder() {
        let session = makeSession(at: "braise")
        XCTAssertEqual(engine.abandon(session), [.cancelTimer(id: "timer.hongshaorou.braise")])
    }

    func testFullRunFinishes() {
        var session = makeSession(at: "braise")
        _ = engine.tick(&session, now: t0.addingTimeInterval(20))
        _ = engine.proceedAfterCheck(&session, now: t0.addingTimeInterval(25))
        _ = engine.confirm(&session, stepID: "reduce", now: t0.addingTimeInterval(300))
        XCTAssertTrue(session.isFinished)
        XCTAssertNil(engine.step(of: session))
        XCTAssertEqual(session.confirmCount, 5)
        XCTAssertTrue(engine.confirm(&session, stepID: "reduce", now: t0).isEmpty)
    }

    // MARK: 持久化

    func testSessionStoreRoundTripAndUnfinishedFilter() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir)
        XCTAssertNil(store.load())

        var session = makeSession(at: "braise")
        store.save(session)
        XCTAssertEqual(SessionStore(directory: dir).loadUnfinished(recipeID: "hongshaorou"), session)

        session.phase = .finished
        store.save(session)
        XCTAssertNil(store.loadUnfinished(recipeID: "hongshaorou"))
        store.clear()
        XCTAssertNil(store.load())
    }

    func testNoteStore() {
        let suite = "food.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let notes = NoteStore(defaults: defaults)
        XCTAssertNil(notes.note(for: "hongshaorou"))
        notes.setNote("  下次少放五克糖 \n", for: "hongshaorou")
        XCTAssertEqual(notes.note(for: "hongshaorou"), "下次少放五克糖")
        notes.setNote("", for: "hongshaorou")
        XCTAssertNil(notes.note(for: "hongshaorou"))
    }
}
