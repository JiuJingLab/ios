import AVFoundation
import Vision

enum InspectionMode: String, CaseIterable {
    case preview = "目視", infrared = "紅外線亮點", visual = "即時視覺"
}

struct BrightSpot: Equatable {
    let x: Double
    let y: Double
    let area: Int
}

enum BrightSpotDetector {
    // Connected components on a bounded luminance grid. Broad lamps and bright rooms
    // are rejected; isolated saturated pixels remain only optical clues, never IR proof.
    static func detect(luma: [UInt8], width: Int, height: Int) -> [BrightSpot] {
        guard width > 2, height > 2, luma.count == width * height else { return [] }
        let mean = Double(luma.reduce(0) { $0 + Int($1) }) / Double(luma.count)
        guard mean < 150 else { return [] }
        let threshold = max(220, Int(mean) + 80)
        var visited = [Bool](repeating: false, count: luma.count)
        var spots: [BrightSpot] = []
        for start in luma.indices where !visited[start] && Int(luma[start]) >= threshold {
            var queue = [start], cursor = 0, sumX = 0, sumY = 0
            visited[start] = true
            while cursor < queue.count {
                let i = queue[cursor]; cursor += 1
                let x = i % width, y = i / width
                sumX += x; sumY += y
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let next = ny * width + nx
                    if !visited[next], Int(luma[next]) >= threshold { visited[next] = true; queue.append(next) }
                }
            }
            if (1...max(2, luma.count / 100)).contains(queue.count) {
                spots.append(BrightSpot(x: (Double(sumX) / Double(queue.count) + 0.5) / Double(width),
                                        y: (Double(sumY) / Double(queue.count) + 0.5) / Double(height), area: queue.count))
            }
        }
        return Array(spots.sorted { $0.area > $1.area }.prefix(12))
    }
}

struct FrameClues {
    let spots: [BrightSpot]
    let housings: Int
    let error: String?
    var summary: String {
        if let error { return error }
        return "本幀：\(spots.count) 個孤立亮點、\(housings) 個含亮點的矩形輪廓。僅供人工複查。"
    }
}

// The capture session and this delegate share one serial queue. At most two frames
// per second are analyzed, late frames are dropped, and no frame leaves memory.
final class FrameAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var mode: InspectionMode = .preview
    var report: ((FrameClues) -> Void)?
    private var lastTime = -Double.infinity
    func reset() { lastTime = -Double.infinity }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard mode != .preview else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time.isFinite, time - lastTime >= 0.5,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastTime = time
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { CVPixelBufferUnlockBaseAddress(buffer, .readOnly); return }
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let gridWidth = 96, gridHeight = max(3, Int(Double(height) / Double(width) * 96))
        var luma = [UInt8](repeating: 0, count: gridWidth * gridHeight)
        for y in 0..<gridHeight {
            for x in 0..<gridWidth {
                // Maximum of a small cell sample preserves small light sources.
                var value: UInt8 = 0
                for dy in 0..<3 {
                    for dx in 0..<3 {
                        let px = min(width - 1, (x * 3 + dx) * width / (gridWidth * 3))
                        let py = min(height - 1, (y * 3 + dy) * height / (gridHeight * 3))
                        let i = py * stride + px * 4
                        let brightness = (Int(pixels[i]) * 29 + Int(pixels[i + 1]) * 150 + Int(pixels[i + 2]) * 77) >> 8
                        value = max(value, UInt8(brightness))
                    }
                }
                luma[y * gridWidth + x] = value
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        let spots = BrightSpotDetector.detect(luma: luma, width: gridWidth, height: gridHeight)
        var housings = 0
        if mode == .visual {
            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 12
            request.minimumConfidence = 0.6
            request.minimumSize = 0.03
            request.minimumAspectRatio = 0.2
            do {
                try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
                housings = (request.results ?? []).filter { rectangle in
                    spots.contains { rectangle.boundingBox.contains(CGPoint(x: $0.x, y: 1 - $0.y)) }
                }.count
            } catch {
                report?(FrameClues(spots: spots, housings: 0, error: "視覺分析失敗，請重新啟動相機；此幀結果不完整。")); return
            }
        }
        report?(FrameClues(spots: spots, housings: housings, error: nil))
    }
}
