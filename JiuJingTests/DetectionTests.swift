import XCTest
import Network
@testable import JiuJing

final class DetectionTests: XCTestCase {
    func testIncompleteAndFailedScansNeverClaimNoSuspiciousFindings() {
        for phase in [ScanPhase.idle, .scanning, .partial, .failed] {
            let summary = ScanSummary(phase: phase, findings: [])
            XCTAssertFalse(summary.title.contains("未發現"))
        }
        XCTAssertEqual(ScanSummary(phase: .completed, findings: []).title, "本輪未發現可疑線索")
    }
    func testReviewFindingsStayProminentEvenWhenScanIsInterrupted() {
        let finding = Finding(id: "test", name: "IP Camera", source: .network, address: "192.0.2.1", reasons: ["RTSP"])
        for phase in [ScanPhase.scanning, .completed, .partial, .failed] {
            let summary = ScanSummary(phase: phase, findings: [finding])
            XCTAssertEqual(summary.reviewCount, 1)
            XCTAssertTrue(summary.caution)
            XCTAssertTrue(summary.title.contains("待確認"))
        }
    }
    @MainActor
    func testNetworkCancellationResetsPhaseAndSuppressesLateCallbacks() async {
        let scanner = NetworkScanner()
        scanner.start()
        XCTAssertEqual(scanner.phase, .scanning)
        scanner.stop()
        XCTAssertEqual(scanner.phase, .partial)
        scanner.clear()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(scanner.phase, .idle)
        XCTAssertTrue(scanner.findings.isEmpty)
        XCTAssertFalse(scanner.running)
    }
    @MainActor
    func testCameraStopInvalidatesPendingStart() async {
        let camera = CameraController()
        camera.start()
        camera.stop()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(camera.state, .idle)
        XCTAssertFalse(camera.torchOn)
        XCTAssertFalse(camera.session.isRunning)
    }
    func testRealBundleRulesDecode() throws {
        let rules = try DetectionRules.load()
        XCTAssertEqual(rules.version, 1)
        XCTAssertEqual(Set(rules.ports).count, rules.ports.count)
        XCTAssertFalse(rules.reasons(name: "V380 Camera").isEmpty)
    }
    func testCommonPortsAndSignalAreNotCameraProof() throws {
        let rules = try DetectionRules.load()
        XCTAssertTrue(rules.reasons(name: "Office printer", ports: [80, 443, 8080]).isEmpty)
        XCTAssertFalse(rules.reasons(name: "Unknown", ports: [554]).isEmpty)
        XCTAssertFalse(rules.reasons(name: "Unknown", services: ["_rtsp._tcp"]).isEmpty)
        XCTAssertFalse(rules.reasons(name: "Unknown", services: ["_axis-video._tcp"]).isEmpty)
        XCTAssertFalse(rules.reasons(name: "Unknown", services: ["_RTSP._TCP."]).isEmpty)
        XCTAssertFalse(rules.reasons(name: "My IPCAM").isEmpty)
        XCTAssertTrue(rules.reasons(name: "").isEmpty)
    }
    func testSubnetExcludesSelfNetworkAndBroadcast() throws {
        let subnet = try XCTUnwrap(IPv4Subnet(address: "192.168.1.12", mask: "255.255.255.0"))
        XCTAssertEqual(subnet.hosts.count, 253)
        for host in ["192.168.1.0", "192.168.1.12", "192.168.1.255"] { XCTAssertFalse(subnet.hosts.contains(host)) }
        XCTAssertFalse(subnet.isPartial)
    }
    func testSmallSubnetNeverEscapesItsMask() throws {
        let subnet = try XCTUnwrap(IPv4Subnet(address: "10.0.0.5", mask: "255.255.255.252"))
        XCTAssertEqual(subnet.hosts, ["10.0.0.6"])
    }
    func testLargeSubnetIsBoundedAndReportsPartialCoverage() throws {
        let subnet = try XCTUnwrap(IPv4Subnet(address: "10.8.3.9", mask: "255.255.0.0"))
        XCTAssertTrue(subnet.isPartial)
        XCTAssertEqual(subnet.hosts.count, 255)
        XCTAssertTrue(subnet.hosts.allSatisfy { $0.hasPrefix("10.8.3.") })
    }
    func testInvalidAndHostOnlyNetworks() {
        for ip in ["1.2.3", "256.1.2.3", "1..2.3", "a.1.2.3", "-1.2.3.4"] { XCTAssertNil(IPv4Subnet(address: ip, mask: "255.255.255.0")) }
        XCTAssertNil(IPv4Subnet(address: "10.0.0.1", mask: "255.0.255.0"))
        XCTAssertNil(IPv4Subnet(address: "10.0.0.1", mask: "0.0.0.0"))
        XCTAssertEqual(IPv4Subnet(address: "10.0.0.1", mask: "255.255.255.255")?.hosts, [])
    }
    @MainActor
    func testStopAndClearAreIdempotent() {
        let network = NetworkScanner()
        network.stop(); network.clear(); network.stop()
        XCTAssertFalse(network.running)
        XCTAssertTrue(network.findings.isEmpty)
        let bluetooth = BluetoothScanner()
        bluetooth.stop(); bluetooth.clear(); bluetooth.stop()
        XCTAssertFalse(bluetooth.running)
        XCTAssertTrue(bluetooth.findings.isEmpty)
    }
    func testTCPProbeFindsListeningPortAndCompletesOnlyOnce() throws {
        let ready = expectation(description: "loopback listener ready")
        let found = expectation(description: "open port")
        found.assertForOverFulfill = true
        let listener = try NWListener(using: .tcp, on: .any)
        var accepted: [NWConnection] = []
        listener.newConnectionHandler = { connection in accepted.append(connection); connection.start(queue: .main) }
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.start(queue: .main)
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port?.rawValue)
        let probe = TCPProbe(host: "127.0.0.1", port: port) { result in
            XCTAssertEqual(result, .open); found.fulfill()
        }
        probe.start()
        wait(for: [found], timeout: 5)
        probe.cancel(); listener.cancel(); accepted.forEach { $0.cancel() }
    }
    func testCancelledProbeNeverReportsResult() {
        let callback = expectation(description: "cancelled callback")
        callback.isInverted = true
        let probe = TCPProbe(host: "127.0.0.1", port: 9) { _ in callback.fulfill() }
        probe.start(); probe.cancel()
        wait(for: [callback], timeout: 1)
    }
}
