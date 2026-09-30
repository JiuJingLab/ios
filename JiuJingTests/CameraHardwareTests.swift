import XCTest
import AVFoundation
@testable import JiuJing

/// Run explicitly on an authorized physical device. No photo/video output or preview is attached.
final class CameraHardwareTests: XCTestCase {
    @MainActor
    func testPhysicalCameraZoomTorchSwitchAndStop() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical camera validation requires a real device and user permission")
        #else
        let camera = CameraController()
        defer { camera.stop() }
        camera.start()
        for _ in 0..<600 {
            if camera.state != .requesting { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(camera.state, .running, camera.message)
        guard camera.state == .running else { return }
        XCTAssertTrue(camera.session.isRunning)
        let back = try XCTUnwrap((camera.session.inputs.first as? AVCaptureDeviceInput)?.device)
        XCTAssertEqual(back.position, .back)
        camera.setZoom(2)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(back.videoZoomFactor, min(2, back.activeFormat.videoMaxZoomFactor), accuracy: 0.05)
        if camera.hasTorch {
            camera.toggleTorch()
            try await Task.sleep(nanoseconds: 500_000_000)
            XCTAssertTrue(camera.torchOn)
            XCTAssertEqual(back.torchMode, .on)
            camera.toggleTorch()
            try await Task.sleep(nanoseconds: 500_000_000)
            XCTAssertFalse(camera.torchOn)
            XCTAssertEqual(back.torchMode, .off)
        }
        camera.switchCamera()
        for _ in 0..<100 {
            if camera.state != .requesting { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(camera.state, .running, camera.message)
        XCTAssertEqual((camera.session.inputs.first as? AVCaptureDeviceInput)?.device.position, .front)
        camera.stop()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(camera.session.isRunning)
        XCTAssertFalse(camera.torchOn)
        XCTAssertEqual(camera.state, .idle)
        #endif
    }
}
