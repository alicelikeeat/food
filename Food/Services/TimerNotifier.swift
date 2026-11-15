import Foundation
import UserNotifications

protocol TimerNotifying: AnyObject {
    func requestAuthorization()
    func schedule(id: String, deadline: Date, title: String, body: String)
    func cancel(id: String)
}

/// 每个活动计时对应一个稳定 ID 的本地通知。同 ID 再次添加会替换原提醒。
final class UserNotificationTimerNotifier: NSObject, TimerNotifying, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

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

    /// App 在前台时由 App 自己播报并显示到期状态，系统通知不再出声或弹出，避免同一次到期提醒两遍。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
