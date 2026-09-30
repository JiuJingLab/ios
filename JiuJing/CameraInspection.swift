import SwiftUI
import AVFoundation

enum CameraState { case idle, requesting, running, blocked, unavailable, failed }

// Capture and in-memory frame analysis share one serial queue. No recording output is installed.
private final class CameraSession {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "org.jiujinglab.camera")
    private var device: AVCaptureDevice?
    private var observers: [NSObjectProtocol] = []
    private var report: ((CameraState, String, Bool) -> Void)?
    private let analyzer = FrameAnalyzer()
    private let output = AVCaptureVideoDataOutput()

    init() {
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self else { return }
                    self.stopHardware()
                    self.report?(.failed, "相機已中斷，請關閉其他相機 App 後重新啟動。", false)
                }
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start(front: Bool, mode: InspectionMode, clues: @escaping (FrameClues) -> Void,
               report: @escaping (CameraState, String, Bool) -> Void) {
        queue.async {
            self.report = report
            self.stopHardware()
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back) else {
                report(.unavailable, "此裝置沒有可用相機；請使用實體 iPhone 或 iPad。", false); return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.outputs.forEach { self.session.removeOutput($0) }
                self.session.sessionPreset = .vga640x480
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    report(.failed, "無法使用此相機，請稍後再試。", false); return
                }
                self.session.addInput(input)
                if mode != .preview {
                    self.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    self.output.alwaysDiscardsLateVideoFrames = true
                    self.output.setSampleBufferDelegate(self.analyzer, queue: self.queue)
                    guard self.session.canAddOutput(self.output) else {
                        self.session.commitConfiguration()
                        report(.failed, "無法啟用逐幀分析，請改用目視模式。", false); return
                    }
                    self.session.addOutput(self.output)
                    if let connection = self.output.connection(with: .video), connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
                self.analyzer.mode = mode; self.analyzer.report = clues; self.analyzer.reset()
                self.session.commitConfiguration()
                self.device = device
                try device.lockForConfiguration()
                device.videoZoomFactor = 1
                device.unlockForConfiguration()
                self.session.startRunning()
                report(self.session.isRunning ? .running : .failed,
                       self.session.isRunning ? "即時預覽中 · 不拍照、不錄影、不上傳" : "相機未能啟動，請稍後重試。",
                       self.session.isRunning && device.hasTorch && device.isTorchAvailable)
            } catch { report(.failed, "相機啟動失敗，請確認沒有其他 App 使用相機。", false) }
        }
    }
    func maximumZoom(_ completion: @escaping (Double) -> Void) {
        queue.async { completion(Double(min(4, self.device?.activeFormat.videoMaxZoomFactor ?? 1))) }
    }
    func zoom(_ factor: CGFloat) {
        queue.async {
            guard let device = self.device, self.session.isRunning else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = min(max(1, factor), min(4, device.activeFormat.videoMaxZoomFactor))
                device.unlockForConfiguration()
            } catch { self.report?(.running, "目前無法調整放大倍率。", device.hasTorch && device.isTorchAvailable) }
        }
    }
    func torch(_ enabled: Bool, completion: @escaping (Bool) -> Void) {
        queue.async {
            guard let device = self.device, self.session.isRunning, device.hasTorch, device.isTorchAvailable else { completion(false); return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if enabled { try device.setTorchModeOn(level: 0.3) } else { device.torchMode = .off }
                completion(device.torchMode == .on)
            } catch { completion(false) }
        }
    }
    func stop() {
        queue.async { self.report = nil; self.stopHardware() }
    }
    private func stopHardware() {
        analyzer.report = nil
        if let device, device.hasTorch {
            if (try? device.lockForConfiguration()) != nil {
                device.torchMode = .off
                device.unlockForConfiguration()
            }
        }
        if session.isRunning { session.stopRunning() }
        device = nil
    }
}

@MainActor
final class CameraController: ObservableObject {
    private let capture = CameraSession()
    var session: AVCaptureSession { capture.session }
    @Published private(set) var state: CameraState = .idle
    @Published private(set) var message = "相機只在你啟動後開啟，畫面留在手機。"
    @Published private(set) var hasTorch = false
    @Published private(set) var torchOn = false
    @Published private(set) var front = false
    @Published var zoom = 1.0
    @Published private(set) var maximumZoom = 1.0
    @Published private(set) var mode: InspectionMode = .preview
    @Published private(set) var clues: FrameClues?
    private var generation = UUID()

    func start() {
        let token = UUID(); generation = token
        state = .requesting
        Task {
            guard generation == token else { return }
            #if targetEnvironment(simulator)
            guard generation == token else { return }
            state = .unavailable; message = "模擬器無法驗證相機；請使用實體 iPhone 或 iPad。"
            return
            #else
            let permission = AVCaptureDevice.authorizationStatus(for: .video)
            var allowed = permission == .authorized
            if permission == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
            guard generation == token else { return }
            guard allowed else {
                state = .blocked; message = "相機權限未允許。可到系統設定開啟，或繼續使用 Wi-Fi／BLE。"; return
            }
            capture.start(front: front, mode: mode, clues: { [weak self] clues in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.clues = clues
                }
            }) { [weak self] state, message, torch in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.state = state; self.message = message; self.hasTorch = torch
                    if state != .running { self.torchOn = false; self.clues = nil }
                    if state == .running {
                        self.capture.maximumZoom { [weak self] maximum in
                            Task { @MainActor in
                                guard let self, self.generation == token else { return }
                                self.maximumZoom = maximum
                            }
                        }
                    }
                }
            }
            #endif
        }
    }
    func stop() {
        generation = UUID(); capture.stop()
        state = .idle; hasTorch = false; torchOn = false; zoom = 1; maximumZoom = 1
        clues = nil
        message = "相機已停止，畫面未儲存。"
    }
    func switchCamera() { stop(); front.toggle(); start() }
    func selectMode(_ mode: InspectionMode) {
        let wasRunning = state == .running
        stop(); self.mode = mode
        if wasRunning { start() }
    }
    func setZoom(_ value: Double) { capture.zoom(CGFloat(value)) }
    func toggleTorch() {
        let token = generation
        capture.torch(!torchOn) { [weak self] enabled in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.torchOn = enabled
                if !enabled { self.message = "補光已關閉或目前無法使用。" }
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface(); view.preview.session = session; view.preview.videoGravity = .resizeAspectFill; return view
    }
    func updateUIView(_ view: PreviewSurface, context: Context) { view.setNeedsLayout() }
    final class PreviewSurface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let orientation = window?.windowScene?.interfaceOrientation, let connection = preview.connection,
                  connection.isVideoOrientationSupported else { return }
            switch orientation {
            case .landscapeLeft: connection.videoOrientation = .landscapeLeft
            case .landscapeRight: connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            default: connection.videoOrientation = .portrait
            }
        }
    }
}

struct CameraInspectionView: View {
    @StateObject private var camera = CameraController()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showIR = false
    @State private var calibrated = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("人工目視輔助 · 不會自動判定攝影機", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                    Picker("相機分析模式", selection: Binding(get: { camera.mode }, set: { camera.selectMode($0); calibrated = false })) {
                        ForEach(InspectionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).disabled(camera.state == .requesting).accessibilityIdentifier("inspectionMode")
                    ZStack {
                        Color.black
                        CameraPreview(session: camera.session).opacity(camera.state == .running ? 1 : 0)
                        if camera.state == .running {
                            Image(systemName: "viewfinder").font(.system(size: 100, weight: .ultraLight)).foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "camera.viewfinder").font(.system(size: 46))
                                Text(camera.state == .requesting ? "正在啟動相機…" : "相機尚未啟動").font(.headline)
                            }.foregroundStyle(.white)
                        }
                    }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 22))
                    Text(camera.message).font(.subheadline).accessibilityIdentifier("cameraStatus")
                    if camera.mode != .preview {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("實驗性本機分析").font(.headline)
                            Text(camera.clues?.summary ?? "尚無分析結果；啟動相機後每秒最多分析兩幀。")
                                .accessibilityIdentifier("frameAnalysisResult")
                            if camera.mode == .infrared {
                                Toggle("已用遙控器確認此鏡頭看得到閃光", isOn: $calibrated)
                                Text(calibrated ? "僅確認這支遙控器可見，不代表所有 IR 波段都可見。請關閉補光，降低環境光並緩慢巡視。" : "先展開下方指引，以遙控器檢查鏡頭反應。尚未校驗時，亮點不可解讀為紅外線。")
                                Text("只找孤立亮點，無法分辨紅外線與可見光。光源、反射、過曝均可能誤報；看不到不代表沒有夜視攝影機。")
                            } else {
                                Text("分析孤立反光與包圍亮點的矩形輪廓，協助留意可能的外殼。不具攝影機語意辨識能力；玻璃、螢幕和裝飾品也可能符合。")
                            }
                        }.font(.subheadline).padding().background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                    if camera.state == .running {
                        HStack {
                            Text("放大").font(.subheadline)
                            Slider(value: $camera.zoom, in: 1...max(1.01, camera.maximumZoom))
                                .disabled(camera.maximumZoom <= 1).accessibilityLabel("相機放大倍率")
                                .onChange(of: camera.zoom) { camera.setZoom($0) }
                            Text("\(camera.zoom, specifier: "%.1f")×").monospacedDigit()
                        }
                        HStack {
                            Button { camera.toggleTorch() } label: { Label(camera.torchOn ? "關閉補光" : "開啟補光", systemImage: "flashlight.on.fill") }.disabled(!camera.hasTorch)
                            Spacer()
                            Button { calibrated = false; camera.switchCamera() } label: { Label("切換鏡頭", systemImage: "arrow.triangle.2.circlepath.camera") }
                        }.buttonStyle(.bordered)
                    }
                    Button {
                        if camera.state == .running { camera.stop() } else { camera.start() }
                    } label: {
                        Text(camera.state == .running ? "停止相機" : "啟動相機")
                            .font(.headline).frame(maxWidth: .infinity).padding(12)
                    }.buttonStyle(.borderedProminent).disabled(camera.state == .requesting).accessibilityIdentifier("cameraStart")
                    if camera.state == .blocked {
                        Button("開啟系統設定") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("怎麼看？").font(.title3.bold())
                        Text("緩慢查看插座、時鐘與陌生物件的小孔。可用放大與補光觀察反光，再向管理者確認用途。")
                        Text("玻璃、金屬與合法設備也會反光；亮點不是偷拍證據。不要拆卸物件或直視強光。")
                    }.font(.subheadline)
                    DisclosureGroup("紅外線檢查指引", isExpanded: $showIR) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("手機相機不是紅外線儀器，不同鏡頭的濾光能力不同。")
                            Text("可先以一般電視遙控器對準鏡頭並短按按鍵，觀察是否看到閃光；看不見時，可切換前後鏡頭。看不到不能代表沒有紅外線。")
                            Text("即使看見閃光，也只代表該鏡頭能看見這支遙控器的部分光線，不能證明能看見所有夜視補光。環境中沒有亮點，也不能排除攝影機。")
                        }.font(.subheadline).padding(.top, 10)
                    }.accessibilityIdentifier("infraredGuide")
                }.padding(20)
            }.background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("相機輔助檢查").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完成") { camera.stop(); dismiss() } }
                .onDisappear { camera.stop() }
                .onChange(of: scenePhase) { phase in if phase == .background { camera.stop() } }
        }
    }
}
