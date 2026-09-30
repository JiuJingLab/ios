import SwiftUI
import AVFoundation

struct SpectrumResult {
    let sampleRate: Double
    let levelDBFS: Double
    let peakHz: Double
    let prominenceDB: Double
    let bands: [Double]
    var hasTone: Bool { levelDBFS > -65 && prominenceDB >= 18 && peakHz >= 2000 }
}

enum SpectrumAnalyzer {
    static let size = 2048
    static let bandEdges: [Double] = [0, 500, 1000, 2000, 4000, 8000, 12000, 16000, 24000]

    // Hann-windowed radix-2 FFT. Values are digital dBFS, not calibrated sound pressure.
    static func analyze(_ samples: [Float], sampleRate: Double) -> SpectrumResult? {
        let n = size
        guard samples.count >= n, sampleRate.isFinite, sampleRate >= 8000,
              samples.prefix(n).allSatisfy(\.isFinite) else { return nil }
        var real = [Double](repeating: 0, count: n), imaginary = real
        var sum = 0.0
        for i in 0..<n {
            let value = Double(samples[i]); sum += value * value
            real[i] = value * (0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(n - 1)))
        }
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { real.swapAt(i, j) }
        }
        var length = 2
        while length <= n {
            let angle = -2 * Double.pi / Double(length)
            for base in stride(from: 0, to: n, by: length) {
                for k in 0..<(length / 2) {
                    let a = base + k, b = a + length / 2
                    let c = cos(angle * Double(k)), s = sin(angle * Double(k))
                    let r = real[b] * c - imaginary[b] * s
                    let im = real[b] * s + imaginary[b] * c
                    real[b] = real[a] - r; imaginary[b] = imaginary[a] - im
                    real[a] += r; imaginary[a] += im
                }
            }
            length <<= 1
        }
        var bands = [Double](repeating: 0, count: 8)
        var peak = 0.0, peakIndex = 0, total = 0.0, count = 0
        for i in 1..<(n / 2) {
            let frequency = Double(i) * sampleRate / Double(n)
            let power = real[i] * real[i] + imaginary[i] * imaginary[i]
            if let band = (0..<8).first(where: { frequency >= bandEdges[$0] && frequency < bandEdges[$0 + 1] }) { bands[band] += power }
            if frequency >= 2000 && frequency <= 20000 {
                total += power; count += 1
                if power > peak { peak = power; peakIndex = i }
            }
        }
        let maxBand = max(bands.max() ?? 0, 1e-20)
        return SpectrumResult(sampleRate: sampleRate, levelDBFS: 10 * log10(max(sum / Double(n), 1e-12)),
            peakHz: Double(peakIndex) * sampleRate / Double(n),
            prominenceDB: peak > 1e-20 ? 10 * log10(peak / max(total / Double(max(count, 1)), 1e-20)) : 0,
            bands: bands.map { $0 / maxBand })
    }
}

struct ToneTracker {
    private var previous: Double = 0
    private var streak = 0
    private(set) var persistentHz: Double?
    mutating func add(_ result: SpectrumResult) {
        guard result.hasTone else { streak = 0; previous = 0; return }
        streak = abs(result.peakHz - previous) <= 150 ? streak + 1 : 1
        previous = result.peakHz
        if streak >= 3 { persistentHz = result.peakHz }
    }
}

private final class AudioAnalysisWorker {
    private let queue = DispatchQueue(label: "org.jiujinglab.audio-analysis", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    func submit(_ buffer: AVAudioPCMBuffer, report: @escaping (SpectrumResult) -> Void) {
        guard buffer.frameLength >= SpectrumAnalyzer.size, let channel = buffer.floatChannelData?[0] else { return }
        lock.lock()
        guard !busy else { lock.unlock(); return }
        busy = true; lock.unlock()
        let samples = Array(UnsafeBufferPointer(start: channel, count: SpectrumAnalyzer.size))
        let sampleRate = buffer.format.sampleRate
        queue.async {
            defer { self.lock.lock(); self.busy = false; self.lock.unlock() }
            if let result = SpectrumAnalyzer.analyze(samples, sampleRate: sampleRate) { report(result) }
        }
    }
}

@MainActor
final class AudioController: ObservableObject {
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var message = "啟動後分析 10 秒環境聲音，只在記憶體處理，不儲存或上傳。"
    @Published private(set) var spectrum: SpectrumResult?
    @Published private(set) var progress = 0.0
    @Published private(set) var persistentHz: Double?
    private var engine: AVAudioEngine?
    private var timer: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var generation = UUID()
    private var tracker = ToneTracker()
    private var frames = 0
    private var activated = false
    var running: Bool { phase == .scanning }

    func start() {
        guard !running else { return }
        clear(); phase = .scanning; message = "等待麥克風授權…"
        let token = generation
        Task {
            #if targetEnvironment(simulator)
            guard generation == token else { return }
            phase = .failed; message = "模擬器無法驗收實體麥克風頻率響應，請使用 iPhone 或 iPad。"
            #else
            var allowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                allowed = await AVCaptureDevice.requestAccess(for: .audio)
            }
            guard generation == token else { return }
            guard allowed else { phase = .failed; message = "麥克風權限未允許，可在系統設定開啟後重試。"; return }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .measurement)
                try session.setActive(true); activated = true
                if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                    try session.setPreferredInput(builtIn)
                }
                let engine = AVAudioEngine()
                let input = engine.inputNode, format = input.outputFormat(forBus: 0)
                guard format.channelCount > 0, format.sampleRate >= 8000 else { throw CocoaError(.featureUnsupported) }
                let worker = AudioAnalysisWorker()
                input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                    worker.submit(buffer) { [weak self] result in
                        Task { @MainActor in
                            guard let self, self.generation == token, self.running else { return }
                            self.frames += 1; self.spectrum = result; self.tracker.add(result)
                            self.persistentHz = self.tracker.persistentHz
                        }
                    }
                }
                self.engine = engine
                try engine.start()
                message = "正在分析環境音；請保持安靜。電子聲音也可能來自充電器、燈具或家電。"
                for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, .AVAudioEngineConfigurationChange] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: name == .AVAudioEngineConfigurationChange ? engine : nil, queue: .main) { [weak self] _ in
                        Task { @MainActor in
                            guard let self, self.generation == token else { return }
                            self.stop(); self.message = "音訊已中斷或輸入裝置改變，只有部分結果，請重新檢查。"
                        }
                    })
                }
                timer = Task { [weak self] in
                    for step in 1...10 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled, let self, self.generation == token else { return }
                        self.progress = Double(step) / 10
                    }
                    self?.finish()
                }
            } catch {
                shutdown(); phase = .failed; message = "無法啟動麥克風，請確認輸入裝置並重試。"
            }
            #endif
        }
    }
    func stop() {
        let wasRunning = running
        shutdown()
        if wasRunning { phase = .partial; message = "分析提前停止，只有部分結果，不能據此排除錄音或攝影設備。" }
    }
    func clear() {
        shutdown(); phase = .idle; spectrum = nil; persistentHz = nil; tracker = ToneTracker(); frames = 0; progress = 0
        message = "啟動後分析 10 秒環境聲音，只在記憶體處理，不儲存或上傳。"
    }
    private func finish() {
        shutdown()
        phase = frames > 0 ? .completed : .failed
        message = frames == 0 ? "未取得可分析的音訊，請確認麥克風並重試。" :
            persistentHz == nil ? "本輪未觀察到持續的高頻窄帶音；不能排除無聲或無可測聲音的設備。" :
            "觀察到持續的高頻窄帶音，請對照附近家電並人工確認來源。這不是攝影或錄音設備的專屬特徵。"
    }
    private func shutdown() {
        generation = UUID(); timer?.cancel(); timer = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }; engine = nil
        if activated { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); activated = false }
    }
}

struct AudioInspectionView: View {
    @StateObject private var audio = AudioController()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            List {
                Section("實驗性音訊頻譜") {
                    Text("量測麥克風收到的聲音頻率，不是電磁波探測器，也沒有可通用辨識攝影機的聲紋模型。僅分析聲學窄帶音線索。")
                    Text("聲音只在本機記憶體做頻譜分析，不錄製檔案、不辨識語音、不上傳。請只在你有權檢查的空間啟動。")
                    Text(audio.message).accessibilityIdentifier("audioStatus")
                    if audio.running { ProgressView(value: audio.progress) }
                    Button(audio.running ? "停止音訊分析" : "啟動 10 秒分析") {
                        if audio.running { audio.stop() } else { audio.start() }
                    }.accessibilityIdentifier("audioStart")
                }
                if let result = audio.spectrum {
                    Section("數位量測結果") {
                        LabeledContent("取樣率", value: String(format: "%.0f Hz", result.sampleRate))
                        LabeledContent("理論上限（非保證頻率響應）", value: String(format: "%.0f Hz", result.sampleRate / 2))
                        LabeledContent("數位音量（非環境 dB SPL）", value: String(format: "%.1f dBFS", result.levelDBFS))
                        if let hz = audio.persistentHz { LabeledContent("持續窄帶音線索", value: String(format: "約 %.0f Hz", hz)) }
                        ForEach(0..<8, id: \.self) { band in
                            if SpectrumAnalyzer.bandEdges[band] < result.sampleRate / 2 {
                                VStack(alignment: .leading) {
                                    Text("\(Int(SpectrumAnalyzer.bandEdges[band]))–\(Int(min(SpectrumAnalyzer.bandEdges[band + 1], result.sampleRate / 2))) Hz").font(.caption)
                                    ProgressView(value: result.bands[band]).accessibilityLabel("相對頻帶能量")
                                }
                            }
                        }
                    }
                }
                Section("限制") {
                    Text("麥克風、降噪與取樣率限制可測範圍；無法保證量測超音波。充電器、風扇、燈具、昆蟲與其他聲音都可能誤報。沒有高頻音不代表沒有攝影機或錄音器。")
                    Button("清除結果") { audio.clear() }
                    Button("開啟系統設定") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                }
            }.navigationTitle("音訊線索").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完成") { audio.stop(); dismiss() } }
                .onDisappear { audio.stop() }
                .onChange(of: scenePhase) { if $0 == .background { audio.stop() } }
        }
    }
}
