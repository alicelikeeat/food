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
}
