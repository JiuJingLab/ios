import XCTest

final class JiuJingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testBluetoothStartReportsSimulatorLimitationAndAllowsRetry() {
        let app = XCUIApplication()
        app.launch()
        app.swipeUp()
        app.switches["scanConsent"].tap()
        app.buttons["藍牙 BLE"].tap()
        app.buttons["scanButton"].tap()
        let stopped = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@", "不支援", "已關閉", "未允許")
        expectation(for: stopped, evaluatedWith: app.staticTexts["scanStatus"])
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["Wi-Fi 區網"].isEnabled)
        XCTAssertTrue(app.buttons["scanButton"].isEnabled)
        capture(app, name: "04-bluetooth-unavailable")
    }

    func testNetworkStartStopAndRetry() {
        let app = XCUIApplication()
        app.launch()
        app.swipeUp()
        app.switches["scanConsent"].tap()
        for _ in 0..<2 {
            app.buttons["scanButton"].tap()
            if app.buttons["scanButton"].label.contains("停止") { app.buttons["scanButton"].tap() }
            let stopped = NSPredicate(format: "enabled == true")
            expectation(for: stopped, evaluatedWith: app.buttons["藍牙 BLE"])
            waitForExpectations(timeout: 5)
            XCTAssertFalse(app.staticTexts["scanStatus"].label.contains("安全認證"))
        }
    }

    func testFindingDetailsBackAndClear() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-findings"]
        app.launch()
        app.swipeUp()
        let finding = app.buttons["finding-fixture-rtsp"]
        XCTAssertTrue(finding.waitForExistence(timeout: 5))
        finding.tap()
        XCTAssertTrue(app.navigationBars["線索詳情"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["192.0.2.10"].exists)
        capture(app, name: "05-finding-details-fixture")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["清除"].tap()
        XCTAssertFalse(finding.exists)
        XCTAssertTrue(app.staticTexts["尚無裝置線索"].exists)
    }
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
