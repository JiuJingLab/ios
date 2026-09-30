import XCTest
import AVFoundation
@testable import JiuJing

final class InspectionTests: XCTestCase {
    func testMACNormalizationAndInvalidAddresses() {
        XCTAssertEqual(MACAddress(" 00-40-8c-aB-12-34 ")?.prefix, "00408C")
        XCTAssertEqual(MACAddress("02:12:34:56:78:90")?.isLocal, true)
        for invalid in ["", "00:11:22", "00:11:22:33:44:GG", "00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF", "01:00:5E:00:00:01", "0:11:22:33:44:55", "00:11-22:33:44:55"] {
            XCTAssertNil(MACAddress(invalid), invalid)
        }
    }
    func testOUIBundleAndCautiousMatching() throws {
        let rules = try OUIRules.load()
        XCTAssertEqual(rules.source, "https://standards-oui.ieee.org/oui/oui.csv")
        XCTAssertEqual(rules.entries.count, 121)
        let entry = try XCTUnwrap(rules.entries.first)
        let prefix = Array(entry.prefix)
        let mac = stride(from: 0, to: 6, by: 2).map { String(prefix[$0...($0 + 1)]) }.joined(separator: ":") + ":11:22:33"
        XCTAssertTrue(rules.result(for: mac).contains(entry.organization))
        XCTAssertTrue(rules.result(for: mac).contains("不能判斷"))
        XCTAssertTrue(rules.result(for: "02:40:8C:11:22:33").contains("隨機化"))
        XCTAssertTrue(rules.result(for: "00:00:00:11:22:33").contains("未命中"))
        XCTAssertTrue(rules.result(for: "bad").contains("格式無效"))
    }
    func testWiFiNamesSignalAndMalformedInputs() throws {
        let rules = try DetectionRules.load()
        XCTAssertTrue(WiFiAssessment.result(ssid: "V380-room", rssi: "-40", rules: rules).contains("名稱含有"))
        let ordinary = WiFiAssessment.result(ssid: "Office", rssi: "-20", rules: rules)
        XCTAssertTrue(ordinary.contains("未命中"))
        XCTAssertTrue(ordinary.contains("不作為可疑判定"))
        XCTAssertTrue(WiFiAssessment.result(ssid: "Office", rssi: "", rules: rules).contains("未命中"))
        for signal in ["0", "-128", "NaN", "-50.5"] {
            XCTAssertTrue(WiFiAssessment.result(ssid: "Camera", rssi: signal, rules: rules).contains("RSSI 請填"))
        }
        for name in [" ", String(repeating: "影", count: 11)] {
            XCTAssertTrue(WiFiAssessment.result(ssid: name, rssi: "", rules: rules).contains("1–32 bytes"))
        }
    }
    func testBrightSpotsRejectUniformLightAndLargeLamps() {
        XCTAssertTrue(BrightSpotDetector.detect(luma: [], width: 0, height: 0).isEmpty)
        for value: UInt8 in [0, 100, 255] {
            XCTAssertTrue(BrightSpotDetector.detect(luma: Array(repeating: value, count: 400), width: 20, height: 20).isEmpty)
        }
        var grid = [UInt8](repeating: 10, count: 400)
        grid[21] = 255; grid[22] = 255
        let spots = BrightSpotDetector.detect(luma: grid, width: 20, height: 20)
        XCTAssertEqual(spots.count, 1)
        XCTAssertEqual(spots.first?.area, 2)
        XCTAssertEqual(spots.first?.x ?? 0, 0.1, accuracy: 0.001)
        for y in 8..<15 { for x in 8..<15 { grid[y * 20 + x] = 255 } }
        XCTAssertEqual(BrightSpotDetector.detect(luma: grid, width: 20, height: 20).count, 1)
    }
    func testFrameDelegateProcessesRealPixelBuffersAndThrottles() throws {
        var pixel: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 96, 96, kCVPixelFormatType_32BGRA, nil, &pixel), kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixel)
        CVPixelBufferLockBaseAddress(buffer, [])
        let pointer = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        memset(pointer, 0, row * 96)
        // A gray rectangular housing with a tiny bright center tests the combined
        // geometry path, independently from the pure bright-component tests.
        for y in 16..<80 { for x in 16..<80 {
            for channel in 0..<3 { pointer[y * row + x * 4 + channel] = 100 }
            pointer[y * row + x * 4 + 3] = 255
        } }
        for channel in 0..<4 { pointer[48 * row + 48 * 4 + channel] = 255 }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: 1, timescale: 1), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample), noErr)
        let analyzer = FrameAnalyzer(), output = AVCaptureVideoDataOutput()
        let connection = AVCaptureConnection(inputPorts: [], output: output)
        var reports: [FrameClues] = []
        analyzer.report = { reports.append($0) }
        analyzer.mode = .infrared
        let frame = try XCTUnwrap(sample)
        analyzer.captureOutput(output, didOutput: frame, from: connection)
        analyzer.captureOutput(output, didOutput: frame, from: connection)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.spots.count, 1)
        analyzer.reset(); analyzer.mode = .visual
        analyzer.captureOutput(output, didOutput: frame, from: connection)
        XCTAssertEqual(reports.count, 2)
        XCTAssertNil(reports.last?.error)
        XCTAssertEqual(reports.last?.housings, 1)
        analyzer.reset(); analyzer.mode = .preview
        analyzer.captureOutput(output, didOutput: frame, from: connection)
        XCTAssertEqual(reports.count, 2)
    }
    private func tone(_ hz: Double, rate: Double = 48000, amplitude: Double = 0.1) -> [Float] {
        (0..<SpectrumAnalyzer.size).map { Float(amplitude * sin(2 * .pi * hz * Double($0) / rate)) }
    }
    func testFFTDetectsToneFrequencyAndDigitalLevelAtMultipleRates() throws {
        for rate in [44100.0, 48000.0] {
            let result = try XCTUnwrap(SpectrumAnalyzer.analyze(tone(6000, rate: rate), sampleRate: rate))
            XCTAssertEqual(result.peakHz, 6000, accuracy: rate / Double(SpectrumAnalyzer.size))
            XCTAssertEqual(result.levelDBFS, -23.01, accuracy: 0.1)
            XCTAssertTrue(result.hasTone)
            XCTAssertEqual(result.bands.count, 8)
            XCTAssertTrue(result.bands.allSatisfy { (0...1).contains($0) })
        }
    }
    func testSilenceLowToneAndBroadbandNoiseDoNotTrigger() throws {
        var seed: UInt64 = 42
        let noise: [Float] = (0..<SpectrumAnalyzer.size).map { _ in
            seed = seed &* 6364136223846793005 &+ 1
            return Float(Double(seed >> 32) / Double(UInt32.max) - 0.5)
        }
        for samples in [[Float](repeating: 0, count: SpectrumAnalyzer.size), tone(500), noise, tone(6000, amplitude: 0.00001)] {
            let result = try XCTUnwrap(SpectrumAnalyzer.analyze(samples, sampleRate: 48000))
            XCTAssertFalse(result.hasTone)
        }
        XCTAssertNil(SpectrumAnalyzer.analyze([], sampleRate: 48000))
        XCTAssertNil(SpectrumAnalyzer.analyze(tone(6000), sampleRate: 0))
        XCTAssertNil(SpectrumAnalyzer.analyze([Float](repeating: .nan, count: SpectrumAnalyzer.size), sampleRate: 48000))
    }
    func testToneRequiresConsecutiveStableObservations() throws {
        var tracker = ToneTracker()
        let a = try XCTUnwrap(SpectrumAnalyzer.analyze(tone(6000), sampleRate: 48000))
        let b = try XCTUnwrap(SpectrumAnalyzer.analyze(tone(9000), sampleRate: 48000))
        tracker.add(a); tracker.add(a); XCTAssertNil(tracker.persistentHz)
        tracker.add(b); XCTAssertNil(tracker.persistentHz)
        tracker.add(b); tracker.add(b); XCTAssertNotNil(tracker.persistentHz)
    }
    @MainActor
    func testInspectionCancellationDiscardsPendingWork() async {
        let audio = AudioController()
        audio.start(); audio.stop()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(audio.phase, .partial)
        XCTAssertNil(audio.spectrum)
        audio.clear(); XCTAssertEqual(audio.phase, .idle)
        let camera = CameraController()
        camera.selectMode(.visual); camera.start(); camera.stop()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(camera.state, .idle); XCTAssertNil(camera.clues)
        let wifi = CurrentWiFi()
        wifi.cancel(); wifi.clear()
        XCTAssertFalse(wifi.loading); XCTAssertEqual(wifi.ssid, "")
    }
}
