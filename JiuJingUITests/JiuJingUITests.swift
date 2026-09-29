import XCTest

final class JiuJingUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testConsentRequiredAndModeSwitch() {
        let app = XCUIApplication()
        app.launch()
        capture(app, name: "01-home")
        let scan = app.buttons["scanButton"]
        app.swipeUp()
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        XCTAssertFalse(scan.isEnabled)
        app.switches["scanConsent"].tap()
        XCTAssertTrue(scan.isEnabled)
        app.buttons["藍牙 BLE"].tap()
        XCTAssertTrue(app.staticTexts["掃描附近 BLE 廣播，不連線、不配對"].exists)
        capture(app, name: "02-bluetooth")
        // No real network or Bluetooth scan is initiated by UI tests.
    }
    func testPrivacyAndGuideAreReachable() {
        let app = XCUIApplication()
        app.launch()
        app.swipeUp()
        app.buttons["隱私"].tap()
        XCTAssertTrue(app.navigationBars["隱私與資料"].waitForExistence(timeout: 3))
        capture(app, name: "03-privacy")
        app.buttons["完成"].tap()
        app.buttons.containing(.staticText, identifier: "再多看一眼").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["多一層檢查"].waitForExistence(timeout: 3))
    }
}
