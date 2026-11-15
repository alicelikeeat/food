import Foundation
import UserNotifications

protocol TimerNotifying: AnyObject {
    /// 做菜页在前台显示时为 true：到点由 App 自己播报，系统通知不再弹出。
    /// 其余时候（例如焖煮中回到首页）前台也要弹出通知，否则到点没有任何提醒。
    var appHandlesForegroundAlerts: Bool { get set }
    func requestAuthorization()
    func schedule(id: String, deadline: Date, title: String, body: String)
    func cancel(id: String)
}

/// 每个活动计时对应一个稳定 ID 的本地通知。同 ID 再次添加会替换原提醒。
final class UserNotificationTimerNotifier: NSObject, TimerNotifying, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let lock = NSLock()
    private var _appHandlesForegroundAlerts = false

    /// 通知代理可能在非主线程回调，所以加锁。
    var appHandlesForegroundAlerts: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _appHandlesForegroundAlerts }
        set { lock.lock(); defer { lock.unlock() }; _appHandlesForegroundAlerts = newValue }
    }

    static func foregroundPresentation(appHandlesAlerts: Bool) -> UNNotificationPresentationOptions {
        appHandlesAlerts ? [] : [.banner, .list, .sound]
    }

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func schedule(id: String, deadline: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let interval = max(1, deadline.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.removeDeliveredNotifications(withIdentifiers: [id])
        // 权限被拒时 add 会静默失败，前台计时不受影响。
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// 做菜页在前台时由 App 自己播报并显示到期状态，系统通知不再出声或弹出，避免同一次到期提醒两遍。
    /// 不在做菜页（首页、备注页等）时照常弹出，因为那时没有人在播报。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.foregroundPresentation(appHandlesAlerts: appHandlesForegroundAlerts))
    }
}
