import XCTest

final class JiuJingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testBluetoothStartReportsSimulatorLimitationAndAllowsRetry() {
        let app = XCUIApplication()
        app.launch()
        app.swipeUp()
        tap(app.switches["scanConsent"], in: app)
        tap(app.buttons["藍牙 BLE"], in: app)
        tap(app.buttons["scanButton"], in: app)
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
        tap(app.switches["scanConsent"], in: app)
        for _ in 0..<2 {
            tap(app.buttons["scanButton"], in: app)
            if app.buttons["scanButton"].label.contains("停止") { tap(app.buttons["scanButton"], in: app) }
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
        tap(finding, in: app)
        XCTAssertTrue(app.navigationBars["線索詳情"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["192.0.2.10"].exists)
        capture(app, name: "05-finding-details-fixture")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.buttons["清除"], in: app)
        XCTAssertFalse(finding.exists)
        XCTAssertTrue(app.staticTexts["尚無裝置線索"].exists)
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { element.tap(); return }
            app.swipeUp()
        }
        XCTFail("Element not reachable: \(element)")
    }
    func testResultSummariesForBothScanModes() {
        for source in ["network", "bluetooth"] {
            for (scenario, title) in [("review", "發現 1 筆待確認線索"), ("empty", "本輪未發現可疑線索"), ("partial", "掃描未完成"), ("failed", "目前無法完成掃描")] {
                let app = XCUIApplication()
                app.launchArguments = ["--ui-test-scan", "\(source):\(scenario)"]
                app.launch()
                XCTAssertTrue(app.staticTexts["resultHeadline"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.staticTexts["resultHeadline"].label, title)
                capture(app, name: "v02-\(source)-\(scenario)")
                if scenario == "review" {
                    tap(app.buttons["reviewFindings"], in: app)
                    XCTAssertTrue(app.buttons["finding-fixture-rtsp"].exists)
                }
                app.terminate()
            }
        }
    }
    func testLargeTypeAndDarkModeSummary() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-scan", "network:review", "--ui-test-accessibility"]
        app.launch()
        XCTAssertTrue(app.staticTexts["resultHeadline"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["resultHeadline"].label, "發現 1 筆待確認線索")
        capture(app, name: "v02-large-type-dark")
        tap(app.buttons["reviewFindings"], in: app)
        XCTAssertTrue(app.buttons["finding-fixture-rtsp"].exists)
    }
    func testCameraUnavailableAndInfraredGuide() {
        let app = XCUIApplication()
        app.launch()
        tap(app.buttons["cameraInspection"], in: app)
        XCTAssertTrue(app.navigationBars["相機輔助檢查"].waitForExistence(timeout: 5))
        tap(app.buttons["cameraStart"], in: app)
        let unavailable = NSPredicate(format: "label CONTAINS %@", "模擬器")
        expectation(for: unavailable, evaluatedWith: app.staticTexts["cameraStatus"])
        waitForExpectations(timeout: 5)
        capture(app, name: "v02-camera-unavailable")
        tap(app.buttons["infraredGuide"], in: app)
        XCTAssertTrue(app.staticTexts["手機相機不是紅外線儀器，不同鏡頭的濾光能力不同。"].exists)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["scanButton"].exists)
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
        tap(app.switches["scanConsent"], in: app)
        XCTAssertTrue(scan.isEnabled)
        tap(app.buttons["藍牙 BLE"], in: app)
        XCTAssertTrue(app.staticTexts["掃描附近 BLE 廣播，不連線、不配對"].exists)
        capture(app, name: "02-bluetooth")
        // No real network or Bluetooth scan is initiated by UI tests.
    }
    func testPrivacyAndGuideAreReachable() {
        let app = XCUIApplication()
        app.launch()
        app.swipeUp()
        tap(app.buttons["隱私"], in: app)
        XCTAssertTrue(app.navigationBars["隱私與資料"].waitForExistence(timeout: 3))
        capture(app, name: "03-privacy")
        app.buttons["完成"].tap()
        tap(app.buttons.containing(.staticText, identifier: "再多看一眼").firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["多一層檢查"].waitForExistence(timeout: 3))
    }
}
