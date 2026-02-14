import XCTest
@testable import NagCore

final class DeepLinkRouterTests: XCTestCase {
  func testReminderDeepLinkParsesRoute() {
    let router = DeepLinkRouter()
    let route = router.route(for: URL(string: "nudge://reminder?id=r1")!)

    XCTAssertEqual(route, .reminder(reminderID: "r1"))
  }

  func testSnoozeDeepLinkParsesRoute() {
    let router = DeepLinkRouter()
    let route = router.route(for: URL(string: "nudge://snooze?reminderID=r1&minutes=20")!)

    XCTAssertEqual(route, .snooze(reminderID: "r1", minutes: 20))
  }

  func testNagScreenDeepLinkParsesRoute() {
    let router = DeepLinkRouter()
    let route = router.route(for: URL(string: "nudge://nag-screen?reminderID=r5")!)

    XCTAssertEqual(route, .nagScreen(reminderID: "r5"))
  }

  func testUnknownDeepLinkReturnsNil() {
    let router = DeepLinkRouter()
    let route = router.route(for: URL(string: "nudge://unknown")!)

    XCTAssertNil(route)
  }
}
