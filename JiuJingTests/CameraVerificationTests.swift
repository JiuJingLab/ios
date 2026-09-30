import XCTest
import Network
import UIKit
@testable import JiuJing

final class CameraVerificationTests: XCTestCase {
    func testTargetsRejectPublicHostsCredentialsAndCrossSubnet() throws {
        for text in ["https://192.168.1.2/x", "http://8.8.8.8/", "http://localhost/", "http://127.0.0.1/", "http://192.168.1.2:0/", "rtsp://user:pass@192.168.1.2/", "http://192.168.1.2/#x", "http://[::1]/", "http://169.254.1.2/", "http://3232235778/"] {
            XCTAssertThrowsError(try CameraTarget(text), text)
        }
        let subnet = try XCTUnwrap(IPv4Subnet(address: "192.168.1.10", mask: "255.255.255.0"))
        XCTAssertTrue(try CameraTarget("rtsp://192.168.1.2:8554/live").isOn(subnet))
        for ip in ["192.168.2.2", "192.168.1.0", "192.168.1.255", "192.168.1.10"] {
            XCTAssertFalse(try CameraTarget("http://\(ip)/").isOn(subnet))
        }
        let target = try CameraTarget("http://192.168.1.2:8080/video?a=1")
        XCTAssertEqual(target.path, "/video?a=1")
        XCTAssertTrue(String(decoding: target.request, as: UTF8.self).contains("Host: 192.168.1.2:8080\r\n"))
    }
    func testHeadersRejectWrongProtocolDuplicateLengthAndSequence() throws {
        let valid = try CameraResponseHead(Data("RTSP/1.0 200 OK\r\nCSeq: 1\r\nContent-Type: application/sdp".utf8), rtsp: true)
        XCTAssertEqual(valid.status, 200)
        for text in ["HTTP/1.1 200 OK\r\nCSeq: 1", "RTSP/1.0 200 OK\r\nCSeq: 2", "RTSP/1.0 200 OK\r\nCSeq: 1\r\nContent-Length: 5\r\nContent-Length: 6", "RTSP/1.0 200 OK\r\nCSeq: 1\r\nContent-Length: 5\r\nTransfer-Encoding: chunked"] {
            XCTAssertThrowsError(try CameraResponseHead(Data(text.utf8), rtsp: true))
        }
        XCTAssertThrowsError(try CameraResponseHead.length("-1", limit: 100))
        XCTAssertThrowsError(try CameraResponseHead.length("999999999999999999999", limit: 100))
        XCTAssertThrowsError(try CameraResponseHead.length("101", limit: 100))
        let head = try CameraResponseHead(Data("HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=\"frame\"".utf8), rtsp: false)
        XCTAssertEqual(head.boundary, "frame")
    }
    private var sdp: Data { Data("v=0\r\no=- 1 1 IN IP4 192.168.1.2\r\ns=Camera\r\nt=0 0\r\nm=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000\r\n".utf8) }
    func testOnlyVideoSDPConfirmsDescription() {
        XCTAssertTrue(VideoDescription.hasVideo(sdp))
        XCTAssertFalse(VideoDescription.hasVideo(Data("<html>m=video 0 RTP/AVP 96</html>".utf8)))
        XCTAssertFalse(VideoDescription.hasVideo(Data("v=0\r\nm=video 0 RTP/AVP 96\r\n".utf8)))
        XCTAssertFalse(VideoDescription.hasVideo(Data(String(decoding: sdp, as: UTF8.self).replacingOccurrences(of: "m=video", with: "m=audio").utf8)))
    }
    func testChunkedTransferAcrossEveryByteAndMalformedChunk() throws {
        var parser = HTTPChunks(), result = Data()
        for byte in Data("4\r\nJPEG\r\n3;foo=bar\r\n123\r\n0\r\n\r\n".utf8) { result.append(try parser.feed(Data([byte]))) }
        XCTAssertEqual(result, Data("JPEG123".utf8)); XCTAssertTrue(parser.finished)
        var invalid = HTTPChunks()
        XCTAssertThrowsError(try invalid.feed(Data("ZZZ\r\n".utf8)))
        var oversized = HTTPChunks()
        XCTAssertThrowsError(try oversized.feed(Data("FFFFFFFFFFFFFFFF\r\n".utf8)))
        var wrongTerminator = HTTPChunks()
        XCTAssertThrowsError(try wrongTerminator.feed(Data("1\r\naXX".utf8)))
    }
    func testMultipartFramesWithAndWithoutLengthAcrossEveryByte() throws {
        let first = Data([0xff, 0xd8, 1, 2, 0xff, 0xd9]), second = Data([0xff, 0xd8, 3, 4, 0xff, 0xd9])
        let body = Data("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(first.count)\r\n\r\n".utf8) + first
            + Data("\r\n--frame\r\nContent-Type: image/jpeg\r\n\r\n".utf8) + second + Data("\r\n--frame--\r\n".utf8)
        var parser = MJPEGFrames(boundary: "frame"), results: [Data] = []
        for byte in body { results += try parser.feed(Data([byte])) }
        XCTAssertEqual(results, [first, second]); XCTAssertTrue(parser.finished)
        var oversized = MJPEGFrames(boundary: "frame")
        XCTAssertThrowsError(try oversized.feed(Data("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: 9999999\r\n\r\n".utf8)))
    }
    private func jpeg(_ color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
    }
    func testJPEGDecodingRejectsTextAndTruncation() throws {
        let data = try jpeg(.red)
        XCTAssertNotNil(VerificationImage.decode(data))
        XCTAssertNil(VerificationImage.decode(Data("<html>camera</html>".utf8)))
        XCTAssertNil(VerificationImage.decode(Data(data.dropLast(10))))
    }
    func testSceneConfirmationRequiresChangingRecentStreamingFrames() {
        let now = Date()
        var evidence = SceneEvidence()
        evidence.record(Data([1]), streaming: true, at: now)
        XCTAssertFalse(evidence.canConfirm(running: true, at: now))
        evidence.record(Data([1]), streaming: true, at: now)
        XCTAssertFalse(evidence.canConfirm(running: true, at: now))
        evidence.record(Data([2]), streaming: true, at: now)
        XCTAssertTrue(evidence.canConfirm(running: true, at: now))
        XCTAssertFalse(evidence.canConfirm(running: false, at: now))
        XCTAssertFalse(evidence.canConfirm(running: true, at: now.addingTimeInterval(4)))
        evidence.record(Data([2]), streaming: true, at: now.addingTimeInterval(4))
        XCTAssertFalse(evidence.canConfirm(running: true, at: now.addingTimeInterval(4)))
        evidence.record(Data([3]), streaming: false, at: now)
        XCTAssertFalse(evidence.canConfirm(running: true, at: now))
    }
    @MainActor
    func testConsentInvalidTargetAndStopNeverConfirm() async {
        let controller = CameraVerificationController()
        controller.start("http://192.168.1.2/", authorized: false)
        XCTAssertFalse(controller.running)
        controller.start("http://8.8.8.8/", authorized: true)
        XCTAssertFalse(controller.running)
        controller.start("http://192.168.1.2/", authorized: true)
        controller.stop(); controller.confirmScene()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(controller.running); XCTAssertFalse(controller.sceneConfirmed)
        XCTAssertEqual(controller.title, "尚未確認")
    }
    @MainActor
    private func exchange(_ response: Data?, rtsp: Bool = true, cancel: Bool = false) async throws -> [CameraVerificationConnection.Event] {
        let ready = expectation(description: "listener ready"), ended = expectation(description: "exchange ended")
        if cancel { ended.isInverted = true }
        let listener = try NWListener(using: .tcp, on: .any)
        var peers: [NWConnection] = []
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.newConnectionHandler = { peer in
            Task { @MainActor in
                peers.append(peer); peer.start(queue: .main)
                peer.receive(minimumIncompleteLength: 1, maximumLength: 4096) { request, _, _, _ in
                    if !cancel { XCTAssertTrue(String(decoding: request ?? Data(), as: UTF8.self).hasPrefix(rtsp ? "DESCRIBE " : "GET ")) }
                    if let response { peer.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in }) }
                }
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let target = try CameraTarget("\(rtsp ? "rtsp" : "http")://192.168.1.2/")
        var events: [CameraVerificationConnection.Event] = []
        let client = CameraVerificationConnection(target: target, connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp)) { event in
            events.append(event)
            if case .ended = event { ended.fulfill() }
        }
        defer { client.cancel(); peers.forEach { $0.cancel() }; listener.cancel() }
        client.start(timeout: 1)
        if cancel { client.cancel() }
        await fulfillment(of: [ended], timeout: cancel ? 0.2 : 5)
        return events
    }
    @MainActor
    func testRTSPLoopbackConfirmsOnlyCompleteVideoDescription() async throws {
        let good = Data("RTSP/1.0 200 OK\r\nCSeq: 1\r\nContent-Type: application/sdp\r\nContent-Length: \(sdp.count)\r\n\r\n".utf8) + sdp
        let events = try await exchange(good)
        XCTAssertEqual(events.filter { if case .videoService = $0 { return true }; return false }.count, 1)
        for response in [Data("RTSP/1.0 401 Unauthorized\r\nCSeq: 1\r\n\r\n".utf8), Data(good.dropLast(10)), Data("HTTP/1.1 200 OK\r\n\r\n".utf8)] {
            let events = try await exchange(response)
            XCTAssertFalse(events.contains { if case .videoService = $0 { return true }; return false })
        }
    }
    @MainActor
    func testHTTPStreamLoopbackDecodesFramesAndRejectsRedirect() async throws {
        let image = try jpeg(.blue)
        let body = Data("--f\r\nContent-Type: image/jpeg\r\nContent-Length: \(image.count)\r\n\r\n".utf8) + image + Data("\r\n--f--\r\n".utf8)
        let response = Data("HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=f\r\nTransfer-Encoding: chunked\r\n\r\n\(String(body.count, radix: 16))\r\n".utf8) + body + Data("\r\n0\r\n\r\n".utf8)
        let events = try await exchange(response, rtsp: false)
        let frames = events.compactMap { event -> Data? in if case .jpeg(let data, let streaming) = event { XCTAssertTrue(streaming); return data }; return nil }
        XCTAssertEqual(frames.count, 1); XCTAssertNotNil(frames.first.flatMap(VerificationImage.decode))
        let redirect = try await exchange(Data("HTTP/1.1 302 Found\r\nLocation: http://8.8.8.8/\r\n\r\n".utf8), rtsp: false)
        XCTAssertFalse(redirect.contains { if case .jpeg = $0 { return true }; return false })
        XCTAssertTrue(redirect.contains { if case .ended(let message) = $0 { return message.contains("重新導向") }; return false })
    }
    @MainActor
    func testHTTPJPEGLoopbackSupportsCloseDelimitedSnapshots() async throws {
        let image = try jpeg(.green)
        let events = try await exchange(Data("HTTP/1.0 200 OK\r\nContent-Type: image/jpeg\r\n\r\n".utf8) + image, rtsp: false)
        XCTAssertTrue(events.contains { event in
            if case .jpeg(let data, let streaming) = event { return !streaming && VerificationImage.decode(data) != nil }
            return false
        })
        let html = try await exchange(Data("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\nCamera".utf8), rtsp: false)
        XCTAssertFalse(html.contains { if case .jpeg = $0 { return true }; return false })
    }
    @MainActor
    func testTimeoutAndCancellationNeverProduceEvidence() async throws {
        let timeout = try await exchange(nil)
        XCTAssertEqual(timeout.count, 1)
        if case .ended(let message) = timeout.first { XCTAssertTrue(message.contains("上限")) } else { XCTFail("Expected timeout") }
        let cancelled = try await exchange(nil, cancel: true)
        XCTAssertTrue(cancelled.isEmpty)
    }
}
