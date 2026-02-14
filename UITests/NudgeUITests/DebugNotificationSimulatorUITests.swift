import XCTest

final class DebugNotificationSimulatorUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testDebugSimulatorCanOpenNagScreen() throws {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-test-debug-notifications")
    app.launch()

    let simulateDeliveryButton = app.buttons["debug.simulateNagDelivery"]
    XCTAssertTrue(simulateDeliveryButton.waitForExistence(timeout: 5))

    simulateDeliveryButton.tap()
    if !app.buttons["Snooze 10 Minutes"].waitForExistence(timeout: 5) {
      simulateDeliveryButton.tap()
    }
    XCTAssertTrue(app.buttons["Snooze 10 Minutes"].waitForExistence(timeout: 8))
  }

  func testDebugSimulatorCanOpenQuickSnoozeSheet() throws {
    let app = XCUIApplication()
    app.launchArguments.append("--ui-test-debug-notifications")
    app.launch()

    let simulateActionButton = app.buttons["debug.simulateNotificationAction"]
    XCTAssertTrue(simulateActionButton.waitForExistence(timeout: 5))

    simulateActionButton.tap()
    XCTAssertTrue(app.buttons["5 min"].waitForExistence(timeout: 8))
  }
}
