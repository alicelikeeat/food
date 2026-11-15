import Foundation

enum SessionPhase: String, Codable {
    /// 等用户点按或语音确认当前步骤。
    case awaitingConfirm
    /// 计时进行中。
    case timerRunning
    /// 计时到点（或用户提前检查），等用户决定继续焖还是下一步。
    case awaitingCheck
    case finished
}

/// 一次做菜的全部可恢复状态。计时只存截止时间，剩余时间永远由「截止时间 − 现在」算出。
struct CookingSession: Codable, Equatable {
    var recipeID: String
    var stepIndex: Int
    var phase: SessionPhase
    var timerDeadline: Date?
    var timerID: String?
    var startedAt: Date
    var finishedAt: Date?
    var confirmCount: Int
    var extendCount: Int

    var isFinished: Bool { phase == .finished }

    func remaining(now: Date) -> TimeInterval {
        guard phase == .timerRunning, let deadline = timerDeadline else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }
}

enum SessionEffect: Equatable {
    case speak(String)
    case scheduleTimer(id: String, deadline: Date, body: String)
    case cancelTimer(id: String)
}

/// 纯逻辑状态机。所有推进都经过这里，UI、语音和通知只是它的输入与副作用。
struct SessionEngine {
    let recipe: Recipe
    /// 测试用短时长：覆盖菜谱里的计时与延长秒数。
    var timerOverride: TimerOverride?
    /// 到点后在这个时间内被发现，视为「前台到点」，由 App 播报；更晚则认为通知已提醒过，不再播报。
    var foregroundGrace: TimeInterval = 3

    struct TimerOverride: Equatable {
        var seconds: Int
        var extendSeconds: Int
    }

    init(recipe: Recipe, timerOverride: TimerOverride? = nil) {
        self.recipe = recipe
        self.timerOverride = timerOverride
    }

    static func timerID(recipeID: String, stepID: String) -> String {
        "timer.\(recipeID).\(stepID)"
    }

    func step(of session: CookingSession) -> RecipeStep? {
        guard recipe.steps.indices.contains(session.stepIndex), !session.isFinished else { return nil }
        return recipe.steps[session.stepIndex]
    }

    func start(now: Date) -> (CookingSession, [SessionEffect]) {
        var session = CookingSession(
            recipeID: recipe.id, stepIndex: 0, phase: .awaitingConfirm,
            timerDeadline: nil, timerID: nil, startedAt: now, finishedAt: nil,
            confirmCount: 0, extendCount: 0
        )
        let effects = enter(index: 0, session: &session, now: now)
        return (session, effects)
    }

    /// 点按与语音确认的唯一入口。`stepID` 是发起确认时用户看到的步骤；
    /// 步骤已变或不在等待确认时直接忽略，所以重复确认不会连跳两步。
    func confirm(_ session: inout CookingSession, stepID: String, now: Date) -> [SessionEffect] {
        guard session.phase == .awaitingConfirm,
              let current = step(of: session), current.id == stepID else { return [] }
        session.confirmCount += 1
        return enter(index: session.stepIndex + 1, session: &session, now: now)
    }

    /// 前台每秒、回到前台、冷启动恢复时调用。到点只会把状态停在「待检查」。
    func tick(_ session: inout CookingSession, now: Date) -> [SessionEffect] {
        guard session.phase == .timerRunning, let deadline = session.timerDeadline,
              now >= deadline, let current = step(of: session) else { return [] }
        session.phase = .awaitingCheck
        var effects: [SessionEffect] = []
        // 清掉待发/已送达的同 ID 通知，保证一次到期只提醒一次。
        if let id = session.timerID { effects.append(.cancelTimer(id: id)) }
        if now.timeIntervalSince(deadline) <= foregroundGrace, let prompt = current.timer?.checkPrompt {
            effects.append(.speak(prompt))
        }
        return effects
    }

    func checkEarly(_ session: inout CookingSession) -> [SessionEffect] {
        guard session.phase == .timerRunning else { return [] }
        session.phase = .awaitingCheck
        session.timerDeadline = nil
        if let id = session.timerID { return [.cancelTimer(id: id)] }
        return []
    }

    /// 「继续焖 N 分钟」：沿用同一个通知 ID 更新提醒。
    func extend(_ session: inout CookingSession, now: Date) -> [SessionEffect] {
        guard session.phase == .awaitingCheck, let current = step(of: session),
              let config = current.timer else { return [] }
        let seconds = timerOverride?.extendSeconds ?? config.extendSeconds
        let deadline = now.addingTimeInterval(TimeInterval(seconds))
        let id = session.timerID ?? Self.timerID(recipeID: recipe.id, stepID: current.id)
        session.phase = .timerRunning
        session.timerDeadline = deadline
        session.timerID = id
        session.extendCount += 1
        return [
            .scheduleTimer(id: id, deadline: deadline, body: config.checkPrompt),
            .speak("好，再焖\(Self.spokenDuration(seconds))。"),
        ]
    }

    func proceedAfterCheck(_ session: inout CookingSession, now: Date) -> [SessionEffect] {
        guard session.phase == .awaitingCheck else { return [] }
        var effects: [SessionEffect] = []
        if let id = session.timerID { effects.append(.cancelTimer(id: id)) }
        session.timerDeadline = nil
        session.timerID = nil
        effects += enter(index: session.stepIndex + 1, session: &session, now: now)
        return effects
    }

    /// 结束或放弃会话时移除提醒。
    func abandon(_ session: CookingSession) -> [SessionEffect] {
        if let id = session.timerID { return [.cancelTimer(id: id)] }
        return []
    }

    private func enter(index: Int, session: inout CookingSession, now: Date) -> [SessionEffect] {
        guard recipe.steps.indices.contains(index) else {
            session.stepIndex = recipe.steps.count
            session.phase = .finished
            session.finishedAt = now
            return [.speak("\(recipe.name)做好了，趁热吃。")]
        }
        let step = recipe.steps[index]
        session.stepIndex = index
        if let config = step.timer {
            let seconds = timerOverride?.seconds ?? config.seconds
            let deadline = now.addingTimeInterval(TimeInterval(seconds))
            let id = Self.timerID(recipeID: recipe.id, stepID: step.id)
            session.phase = .timerRunning
            session.timerDeadline = deadline
            session.timerID = id
            return [
                .scheduleTimer(id: id, deadline: deadline, body: config.checkPrompt),
                .speak(step.spoken),
            ]
        }
        session.phase = .awaitingConfirm
        return [.speak(step.spoken)]
    }

    static func spokenDuration(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 { return "\(seconds / 60)分钟" }
        return "\(seconds)秒"
    }

    static func buttonDuration(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 { return "\(seconds / 60) 分钟" }
        return "\(seconds) 秒"
    }
}
