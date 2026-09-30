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
        for _ in 0..<12 {
            if element.isHittable { element.tap(); return }
            // New inspection entries make the home page taller. Scroll toward the
            // target instead of always downward (which can pass controls above us).
            let above = element.exists && element.frame.midY < app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.35 : 0.7))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.7 : 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
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
    func testMACAndWiFiManualChecks() {
        let app = XCUIApplication()
        app.launch()
        tap(app.buttons["networkClues"], in: app)
        let mac = app.textFields["macInput"]
        tap(mac, in: app); mac.typeText("02:11:22:33:44:55\n")
        tap(app.buttons["matchMAC"], in: app)
        XCTAssertTrue(app.staticTexts["macResult"].label.contains("隨機化"))
        let ssid = app.textFields["ssidInput"]
        tap(ssid, in: app); ssid.typeText("V380-room\n")
        tap(app.buttons["matchWiFi"], in: app)
        XCTAssertTrue(app.staticTexts["wifiResult"].label.contains("名稱含有"))
        capture(app, name: "v03-network-clues")
        tap(app.buttons["清除輸入與結果"], in: app)
        XCTAssertFalse(app.staticTexts["wifiResult"].exists)
    }
    func testAudioUnavailableAndClear() {
        let app = XCUIApplication()
        app.launch()
        tap(app.buttons["audioInspection"], in: app)
        tap(app.buttons["audioStart"], in: app)
        expectation(for: NSPredicate(format: "label CONTAINS %@", "模擬器"), evaluatedWith: app.staticTexts["audioStatus"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["audioStart"].isEnabled)
        capture(app, name: "v03-audio-unavailable")
        tap(app.buttons["清除結果"], in: app)
        XCTAssertTrue(app.staticTexts["audioStatus"].label.contains("啟動後分析"))
    }
    func testCameraAnalysisModesAreReachable() {
        let app = XCUIApplication()
        app.launch()
        tap(app.buttons["cameraInspection"], in: app)
        tap(app.buttons["紅外線亮點"], in: app)
        XCTAssertTrue(app.staticTexts["frameAnalysisResult"].exists)
        tap(app.buttons["即時視覺"], in: app)
        XCTAssertTrue(app.staticTexts["frameAnalysisResult"].label.contains("尚無分析結果"))
        capture(app, name: "v03-camera-analysis")
    }
    func testVerificationRequiresConsentAndRejectsNonLocalAddress() {
        let app = XCUIApplication()
        app.launch()
        tap(app.buttons["cameraVerification"], in: app)
        XCTAssertFalse(app.buttons["verificationStart"].isEnabled)
        let address = app.textFields["verificationAddress"]
        tap(address, in: app); address.typeText("http://8.8.8.8/\n")
        let consent = app.switches["verificationConsent"]
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["verificationStart"].isEnabled)
        tap(app.buttons["verificationStart"], in: app)
        XCTAssertTrue(app.staticTexts["verificationMessage"].label.contains("私有 IPv4"))
        XCTAssertEqual(app.staticTexts["verificationTitle"].label, "尚未確認")
        capture(app, name: "v03-verification-guard")
        tap(app.buttons["清除畫面與結果"], in: app)
        XCTAssertEqual(app.staticTexts["verificationTitle"].label, "尚未確認")
    }
}
