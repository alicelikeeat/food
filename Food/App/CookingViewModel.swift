import Foundation
import SwiftUI
import UIKit

/// 做菜页的唯一状态持有者。把状态机、持久化、通知、播报、语音和锅面画面接在一起。
@MainActor
final class CookingViewModel: ObservableObject {
    let recipe: Recipe
    let hint = HintPlayerModel()
    let voice = VoiceConfirmer()
    let feed: PotFeed

    @Published private(set) var session: CookingSession
    /// 糖色观察的稳定结果。nil 表示尚未稳定或不在观察步骤。
    @Published private(set) var reading: CaramelReading?
    @Published private(set) var feedStatus: FeedStatus = .idle
    @Published var braiseShowsDemo = false { didSet { syncHint() } }
    @Published var braiseShowsPot = false { didSet { syncFeed() } }
    @Published var isMuted: Bool { didSet { announcer.isMuted = isMuted; defaults.set(isMuted, forKey: SettingsKey.muted) } }
    @Published var cameraOff: Bool { didSet { defaults.set(cameraOff, forKey: SettingsKey.cameraOff); syncFeed() } }
    @Published var voiceConfirmEnabled: Bool { didSet { defaults.set(voiceConfirmEnabled, forKey: SettingsKey.voiceConfirm) } }

    private var engine: SessionEngine
    private let store: SessionStore
    private let notes: NoteStore
    private let notifier: TimerNotifying
    private let announcer = SpeechAnnouncer()
    private let defaults: UserDefaults
    private let classifier = CaramelClassifier()
    private var stabilizer = ObservationStabilizer()
    private var sceneActive = true
    private var visible = false
    /// 示范是被切后台（而不是用户）暂停的，回到前台时续播。
    private var hintPausedBySystem = false
    /// 分析是否开着。分析队列上已在途的帧可能在关闭后才送达，靠它丢掉。
    private var analysisActive = false

    init(
        recipe: Recipe,
        resume: CookingSession?,
        store: SessionStore,
        notes: NoteStore,
        notifier: TimerNotifying,
        defaults: UserDefaults = .standard
    ) {
        self.recipe = recipe
        self.store = store
        self.notes = notes
        self.notifier = notifier
        self.defaults = defaults
        let override: SessionEngine.TimerOverride? = defaults.bool(forKey: SettingsKey.shortTimers)
            ? .init(seconds: 20, extendSeconds: 10) : nil
        let engine = SessionEngine(recipe: recipe, timerOverride: override)
        self.engine = engine
        isMuted = defaults.bool(forKey: SettingsKey.muted)
        cameraOff = defaults.bool(forKey: SettingsKey.cameraOff)
        voiceConfirmEnabled = defaults.bool(forKey: SettingsKey.voiceConfirm)

        #if targetEnvironment(simulator)
        feed = SampleFeedController()
        #else
        feed = CameraController()
        #endif

        var pending: [SessionEffect] = []
        if let resume {
            session = resume
        } else {
            let (fresh, effects) = engine.start(now: Date())
            session = fresh
            pending = effects
        }

        announcer.isMuted = isMuted
        announcer.onWillSpeak = { [weak self] in self?.voice.stop() }
        feed.onStatus = { [weak self] status in self?.feedStatus = status }
        feed.onStats = Self.statsHandler(classifier: classifier) { [weak self] reading in
            Task { @MainActor in self?.ingest(reading) }
        }

        store.save(session)
        if resume == nil { notifier.requestAuthorization() }
        run(pending)
        // 恢复时计时可能已在后台到期。
        tick()
    }

    /// 在后台分析队列上运行，所以不能带主线程隔离。
    nonisolated private static func statsHandler(
        classifier: CaramelClassifier,
        deliver: @escaping @Sendable (CaramelReading) -> Void
    ) -> (FrameStats) -> Void {
        { stats in deliver(classifier.classify(stats)) }
    }

    // MARK: - 派生状态

    var currentStep: RecipeStep? { engine.step(of: session) }
    var isTimedStep: Bool { currentStep?.timer != nil }
    var stepCount: Int { recipe.steps.count }
    var extendLabel: String {
        let seconds = engine.timerOverride?.extendSeconds ?? currentStep?.timer?.extendSeconds ?? 300
        return "继续焖 \(SessionEngine.buttonDuration(seconds))"
    }
    var nextStepTitle: String? {
        let next = session.stepIndex + 1
        return recipe.steps.indices.contains(next) ? recipe.steps[next].title : nil
    }
    var voiceButtonVisible: Bool {
        voiceConfirmEnabled && voice.availability == .available && session.phase == .awaitingConfirm
    }
    /// 观察区显示的一句话。看不清或没结果时回到「请对照上方示范」。
    var observationHint: String? {
        guard let target = currentStep?.observation else { return nil }
        guard feedStatus == .running, let reading, reading != .unclear else { return target.fallbackHint }
        return reading.hint
    }

    // MARK: - 用户操作（唯一入口）

    /// 点按和语音确认都走这里。stepID 不匹配当前步骤时被状态机忽略。
    func confirm(stepID: String) {
        voice.stop()
        apply { engine.confirm(&$0, stepID: stepID, now: Date()) }
    }

    func extendBraise() {
        apply { engine.extend(&$0, now: Date()) }
    }

    func proceedAfterCheck() {
        apply { engine.proceedAfterCheck(&$0, now: Date()) }
    }

    func checkEarly() {
        apply { engine.checkEarly(&$0) }
    }

    func tick(now: Date = Date()) {
        guard session.phase == .timerRunning else { return }
        apply { engine.tick(&$0, now: now) }
    }

    func startVoiceConfirm() {
        guard let step = currentStep, session.phase == .awaitingConfirm else { return }
        announcer.stop()
        let stepID = step.id
        voice.listen(phrases: step.confirmPhrases) { [weak self] in
            self?.confirm(stepID: stepID)
        }
    }

    func setVoiceConfirm(_ enabled: Bool) {
        guard enabled else { voiceConfirmEnabled = false; voice.stop(); return }
        Task {
            let granted = await voice.requestPermissions()
            voiceConfirmEnabled = granted
        }
    }

    func repeatInstruction() {
        if let step = currentStep { announcer.speak(step.spoken) }
    }

    /// 中途退出：保留会话与计时，首页可「继续做菜」。
    func leave() {
        visible = false
        notifier.appHandlesForegroundAlerts = false
        voice.stop()
        announcer.stop()
        hint.pause()
        syncFeed()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// 放弃本次做菜：移除提醒并清掉会话。
    func abandon() {
        run(engine.abandon(session))
        store.clear()
        leave()
    }

    func finish(note: String) {
        notes.setNote(note, for: recipe.id)
        run(engine.abandon(session))
        store.clear()
        leave()
    }

    var savedNote: String { notes.note(for: recipe.id) ?? "" }

    // MARK: - 生命周期

    func appeared() {
        visible = true
        notifier.appHandlesForegroundAlerts = true
        voice.refreshAvailability()
        syncAll()
        tick()
    }

    func sceneChanged(active: Bool) {
        sceneActive = active
        if active {
            voice.refreshAvailability()
            tick()
            if hintPausedBySystem {
                hintPausedBySystem = false
                if visible, currentStep != nil { hint.play() }
            }
        } else {
            voice.stop()
            if hint.isPlaying { hintPausedBySystem = true }
            hint.pause()
        }
        syncFeed()
        syncIdleTimer()
    }

    // MARK: - 内部

    private func apply(_ change: (inout CookingSession) -> [SessionEffect]) {
        var next = session
        let effects = change(&next)
        guard next != session || !effects.isEmpty else { return }
        let stepChanged = next.stepIndex != session.stepIndex
        session = next
        store.save(next)
        run(effects)
        if stepChanged {
            braiseShowsDemo = false
            braiseShowsPot = false
        }
        syncAll()
    }

    private func run(_ effects: [SessionEffect]) {
        for effect in effects {
            switch effect {
            case .speak(let text):
                announcer.speak(text)
            case .scheduleTimer(let id, let deadline, let body):
                notifier.schedule(id: id, deadline: deadline, title: "\(recipe.name) · 时间到", body: body)
            case .cancelTimer(let id):
                notifier.cancel(id: id)
            }
        }
    }

    private func ingest(_ value: CaramelReading) {
        guard analysisActive, currentStep?.observation != nil, session.phase == .awaitingConfirm else { return }
        let output = stabilizer.ingest(value)
        if reading != output.display { reading = output.display }
        // 只提示，不换步。收听中不插话。
        if let spoken = output.announce?.spoken, !voice.isListening {
            announcer.speak(spoken)
        }
    }

    private func syncAll() {
        syncHint()
        syncFeed()
        syncIdleTimer()
    }

    private func syncHint() {
        guard visible, let step = currentStep else { hint.pause(); return }
        if step.timer != nil {
            // 焖煮：示范默认收起，展开才加载播放。
            if braiseShowsDemo { hint.load(step: step); if !hint.isPlaying { hint.play() } } else { hint.pause() }
        } else {
            hint.load(step: step)
        }
    }

    /// 根据当前步骤决定相机与分析是否运行。焖煮默认停用，展开「打开锅面」才恢复。
    private func syncFeed() {
        let step = currentStep
        let wanted = visible && sceneActive && !cameraOff && step != nil
            && (step?.timer == nil || braiseShowsPot)
        let analyze = wanted && step?.observation != nil && session.phase == .awaitingConfirm
        if !analyze {
            stabilizer.reset()
            reading = nil
        }
        analysisActive = analyze
        feed.setAnalysis(enabled: analyze)
        if wanted { feed.start() } else { feed.stop() }
    }

    private func syncIdleTimer() {
        // 手上操作的步骤保持亮屏；焖煮时允许锁屏，靠通知提醒。
        UIApplication.shared.isIdleTimerDisabled = visible && sceneActive && currentStep != nil && !isTimedStep
    }
}
