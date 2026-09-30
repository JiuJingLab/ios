import SwiftUI
import Network
import ImageIO
import CryptoKit

@MainActor
final class CameraVerificationConnection {
    enum Event { case videoService, jpeg(Data, streaming: Bool), ended(String) }
    private let connection: NWConnection
    private let target: CameraTarget
    private var report: ((Event) -> Void)?
    private var timer: Task<Void, Never>?
    private var buffer = Data()
    private var head: CameraResponseHead?
    private var chunks = HTTPChunks()
    private var multipart: MJPEGFrames?
    private var expected: Int?
    private var received = 0
    private var bodyReceived = 0
    private var frames = 0

    convenience init(target: CameraTarget, interface: NWInterface?, report: @escaping (Event) -> Void) {
        let parameters = NWParameters.tcp
        if let interface { parameters.requiredInterface = interface }
        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: NWEndpoint.Port(rawValue: target.port)!, using: parameters)
        self.init(target: target, connection: connection, report: report)
    }
    // Injecting a connection allows loopback protocol tests without LAN traffic.
    init(target: CameraTarget, connection: NWConnection, report: @escaping (Event) -> Void) {
        self.target = target; self.connection = connection; self.report = report
    }
    func start(timeout: UInt64 = 30) {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.report != nil else { return }
                switch state {
                case .ready:
                    self.connection.send(content: self.target.request, completion: .contentProcessed { [weak self] error in
                        Task { @MainActor in
                            guard let self, self.report != nil else { return }
                            if error != nil { self.finish("請求失敗，無法確認。") } else { self.receive() }
                        }
                    })
                case .failed: self.finish("連線失敗，無法確認；不代表沒有攝影機。")
                case .waiting:
                    if self.connection.currentPath?.unsatisfiedReason == .localNetworkDenied { self.finish("本機網路權限遭拒，無法確認。") }
                default: break
                }
            }
        }
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finish("已達 \(timeout) 秒上限，連線停止；結果只涵蓋本次回應。")
        }
        connection.start(queue: .main)
    }
    func cancel() {
        report = nil; timer?.cancel(); timer = nil
        connection.stateUpdateHandler = nil; connection.cancel(); buffer = Data(); multipart = nil
    }
    private func finish(_ message: String) {
        let callback = report; cancel(); callback?(.ended(message))
    }
    private func receive() {
        guard report != nil else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32768) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.report != nil else { return }
                do {
                    if let data { try self.consume(data) }
                    guard self.report != nil else { return }
                    if error != nil { self.finish("連線中斷，未完成的部分無法確認。") }
                    else if complete { try self.endOfBody() }
                    else { self.receive() }
                } catch { self.finish(error.localizedDescription) }
            }
        }
    }
    private func consume(_ data: Data) throws {
        received += data.count
        guard received <= 20 * 1024 * 1024 else { throw VerificationError.tooLarge }
        if head == nil {
            buffer.append(data)
            guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if buffer.count > 16384 { throw VerificationError.tooLarge }; return
            }
            let parsed = try CameraResponseHead(Data(buffer[..<range.lowerBound]), rtsp: target.isRTSP)
            head = parsed
            if parsed.status == 401 || parsed.status == 403 { finish("裝置要求授權，尚未確認影像；本工具不嘗試帳密或繞過驗證。"); return }
            if (300...399).contains(parsed.status) { finish("裝置要求重新導向；已停止，不會連往其他位置。"); return }
            guard parsed.status == 200 else { finish("裝置回應狀態 \(parsed.status)，未確認影像；請確認已知的串流路徑。"); return }
            let type = parsed.mediaType
            guard target.isRTSP ? type == "application/sdp" : ["image/jpeg", "multipart/x-mixed-replace"].contains(type) else { throw VerificationError.unsupported }
            if let encoding = parsed.fields["content-encoding"], encoding.lowercased() != "identity" { throw VerificationError.unsupported }
            if let transfer = parsed.fields["transfer-encoding"], (target.isRTSP || transfer.lowercased() != "chunked") { throw VerificationError.unsupported }
            expected = try CameraResponseHead.length(parsed.fields["content-length"], limit: target.isRTSP ? 65536 : type == "image/jpeg" ? MJPEGFrames.maxFrame : 20 * 1024 * 1024)
            if target.isRTSP && expected == nil { throw VerificationError.malformed }
            if type == "multipart/x-mixed-replace" {
                guard let boundary = parsed.boundary else { throw VerificationError.malformed }
                multipart = MJPEGFrames(boundary: boundary)
            }
            let remainder = Data(buffer[range.upperBound...]); buffer = Data()
            try consumeBody(remainder)
        } else { try consumeBody(data) }
    }
    private func consumeBody(_ data: Data) throws {
        bodyReceived += data.count
        if let expected, bodyReceived > expected { throw VerificationError.malformed }
        let payload = head?.fields["transfer-encoding"] != nil ? try chunks.feed(data) : data
        if multipart != nil {
            for frame in try multipart!.feed(payload) {
                frames += 1; report?(.jpeg(frame, streaming: true))
            }
            if multipart?.finished == true { finish("影像串流已結束，共收到 \(frames) 個影像部分。"); return }
        } else {
            buffer.append(payload)
            guard buffer.count <= (target.isRTSP ? 65536 : MJPEGFrames.maxFrame) else { throw VerificationError.tooLarge }
        }
        if chunks.finished || expected == bodyReceived { try endOfBody() }
    }
    private func endOfBody() throws {
        guard let head else { throw VerificationError.malformed }
        if let expected, bodyReceived != expected { throw VerificationError.malformed }
        if head.fields["transfer-encoding"] != nil && !chunks.finished { throw VerificationError.malformed }
        if target.isRTSP {
            if VideoDescription.hasVideo(buffer) {
                report?(.videoService); finish("RTSP 回傳有效 SDP 與 video 軌道；只確認影像服務描述，尚未取得畫面。")
            } else { finish("回應未包含可辨識的影像軌道，無法確認影像服務。") }
        } else if multipart == nil {
            report?(.jpeg(buffer, streaming: false)); finish("已接收單張 JPEG 回應；單張照片不能證明即時拍攝。")
        } else { finish("影像連線已結束；未完成的影像部分不列入確認。") }
    }
}

enum VerificationImage {
    static func decode(_ data: Data) -> UIImage? {
        guard data.count <= MJPEGFrames.maxFrame, data.starts(with: [0xff, 0xd8]), data.suffix(2) == Data([0xff, 0xd9]),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == "public.jpeg",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 8_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct SceneEvidence {
    private(set) var frames = 0
    private(set) var changed = false
    private(set) var streaming = false
    private var previous: SHA256.Digest?
    private var latestTime: Date?
    private var latestChange: Date?
    mutating func record(_ data: Data, streaming: Bool, at date: Date) {
        let digest = SHA256.hash(data: data)
        if let previous, digest != previous { changed = true; latestChange = date }
        previous = digest; frames += 1; self.streaming = streaming; latestTime = date
    }
    func canConfirm(running: Bool, at date: Date) -> Bool {
        guard running, streaming, changed, frames >= 2, let latestTime, let latestChange else { return false }
        return (0...3).contains(date.timeIntervalSince(latestTime)) && (0...3).contains(date.timeIntervalSince(latestChange))
    }
}

@MainActor
final class CameraVerificationController: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var message = "尚未驗證；請提供你有權讀取的裝置串流網址。"
    @Published private(set) var title = "尚未確認"
    @Published private(set) var image: UIImage?
    @Published private(set) var evidence = SceneEvidence()
    @Published private(set) var sceneConfirmed = false
    private var monitor: NWPathMonitor?
    private var connection: CameraVerificationConnection?
    private var deadline: Task<Void, Never>?
    private var generation = UUID()
    private var activeNetwork: String?
    private var lastDecode = Date.distantPast

    func start(_ text: String, authorized: Bool) {
        clear()
        guard authorized else { message = "請先確認你有權讀取此裝置的影像。"; return }
        let target: CameraTarget
        do { target = try CameraTarget(text) } catch { message = error.localizedDescription; return }
        running = true; message = "正在確認目前 Wi-Fi 與目標位址…"
        let token = generation
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self, self.generation == token, self.running else { return }
                let names = Set(path.availableInterfaces.filter { $0.type == .wifi }.map(\.name))
                guard path.status == .satisfied, let (subnet, name) = NetworkScanner.wifiSubnet(names: names), target.isOn(subnet),
                      let interface = path.availableInterfaces.first(where: { $0.name == name && $0.type == .wifi }) else {
                    self.stop(); self.message = "目標不在目前 Wi-Fi 的可用 IPv4 子網，已停止驗證。"; return
                }
                let network = "\(name):\(subnet.address):\(subnet.mask)"
                if let active = self.activeNetwork {
                    if active != network { self.stop(); self.message = "Wi-Fi 已改變，請重新驗證。" }
                    return
                }
                self.activeNetwork = network
                self.connection = CameraVerificationConnection(target: target, interface: interface) { [weak self] event in
                    guard let self, self.generation == token else { return }
                    self.accept(event)
                }
                self.message = target.isRTSP ? "正在驗證 RTSP 影像服務…" : "正在讀取你授權的影像，最多 30 秒…"
                self.connection?.start(timeout: target.isRTSP ? 10 : 30)
            }
        }
        monitor.start(queue: .main)
        deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 35_000_000_000)
            guard !Task.isCancelled, let self, self.generation == token, self.running else { return }
            self.stop(); self.message = "驗證逾時，請檢查網路或權限後重試。"
        }
    }
    private func accept(_ event: CameraVerificationConnection.Event) {
        switch event {
        case .videoService: title = "已確認影像服務描述"
        case .jpeg(let data, let streaming):
            let now = Date()
            guard now.timeIntervalSince(lastDecode) >= 0.5 else { return }
            guard let image = VerificationImage.decode(data) else {
                stop(); message = "收到的資料不是可顯示的 JPEG，或影像尺寸過大；未確認畫面。"; return
            }
            lastDecode = now; self.image = image; evidence.record(data, streaming: streaming, at: now)
            if !sceneConfirmed { title = "已取得影像，來源待確認" }
        case .ended(let message):
            running = false; self.message = message
            monitor?.cancel(); monitor = nil; deadline?.cancel(); deadline = nil; connection = nil
        }
    }
    func confirmScene() {
        guard evidence.canConfirm(running: running, at: Date()) else { return }
        sceneConfirmed = true; title = "使用者已確認本空間畫面"
        message = "你已回報畫面與現場動作同步。這可用於確認拍攝來源；是否未經同意拍攝，仍需確認用途與同意情況。"
    }
    func stop(clearImage: Bool = false) {
        generation = UUID(); connection?.cancel(); connection = nil
        monitor?.cancel(); monitor = nil; deadline?.cancel(); deadline = nil
        running = false; activeNetwork = nil
        message = "連線已停止；保留本次確認狀態，不能視為仍在直播。"
        if clearImage { image = nil }
    }
    func clear() {
        stop(clearImage: true); title = "尚未確認"; evidence = SceneEvidence(); sceneConfirmed = false; lastDecode = .distantPast
        message = "尚未驗證；請提供你有權讀取的裝置串流網址。"
    }
}

struct CameraVerificationView: View {
    @StateObject private var verifier = CameraVerificationController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var address: String
    @State private var authorized = false
    @FocusState private var addressFocused: Bool
    init(finding: Finding? = nil) {
        if let finding, IPv4Subnet.number(finding.address) != nil {
            let rtsp = finding.ports.intersection([554, 8554]).sorted().first
            let port = rtsp ?? finding.ports.intersection([80, 8000, 8080]).sorted().first ?? 80
            _address = State(initialValue: "\(rtsp == nil ? "http" : "rtsp")://\(finding.address):\(port)/")
        } else { _address = State(initialValue: "") }
    }
    var body: some View {
        List {
            Section("驗證裝置是否提供拍攝畫面") {
                Text("名稱和端口只能提供線索；此功能會向指定裝置讀取影像服務描述或實際畫面，協助確認來源。")
                TextField("http://192.168.1.20/video 或 rtsp://…", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .focused($addressFocused).submitLabel(.done).onSubmit { addressFocused = false }
                    .disabled(verifier.running).accessibilityIdentifier("verificationAddress")
                    .onChange(of: address) { _ in verifier.clear(); authorized = false }
                Text("請使用設備文件或管理者提供的 JPEG／MJPEG／RTSP 路徑；預填的 / 不保證是串流路徑。只接受同一 Wi-Fi 的私有 IPv4 位址。")
                    .font(.footnote)
                Toggle("我有權讀取此裝置的影像", isOn: $authorized).disabled(verifier.running).accessibilityIdentifier("verificationConsent")
                Button(verifier.running ? "停止驗證" : "開始驗證") {
                    if verifier.running { verifier.stop() } else { verifier.start(address, authorized: authorized) }
                }.disabled(!authorized && !verifier.running).accessibilityIdentifier("verificationStart")
            }
            Section("確認狀態") {
                Text(verifier.title).font(.headline).accessibilityIdentifier("verificationTitle")
                Text(verifier.message).accessibilityIdentifier("verificationMessage")
                if let image = verifier.image {
                    Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("裝置回傳的最新影像")
                    Text(verifier.running ? "正在接收 · 已顯示 \(verifier.evidence.frames) 幀" : "連線已停止 · 最後收到的畫面")
                        .font(.caption)
                }
                if verifier.evidence.streaming {
                    Text("確認畫面是否為你所在空間；在安全的位置做一個簡單動作（例如舉起兩根手指再放下），觀察畫面是否立即同步。只在親眼確認後按下方按鈕。")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Button("我已看到現場動作即時同步") { verifier.confirmScene() }
                            .disabled(!verifier.evidence.canConfirm(running: verifier.running, at: context.date) || verifier.sceneConfirmed)
                            .accessibilityIdentifier("confirmScene")
                    }
                }
                Button("清除畫面與結果") { verifier.clear() }
            }
            Section("這能確認什麼") {
                Text("RTSP 描述只能確認裝置宣告影像軌道；本版不播放 RTSP。JPEG 是單張照片；MJPEG 可顯示連續影像。取得影像不代表影像是即時拍攝，仍需現場動作核對。")
                Text("本功能不判定是否偷拍或是否合法。若確認未經同意拍攝私密空間，先離開並尋求協助，避免拆卸或破壞設備。")
                Text("不嘗試帳密、不跟隨重新導向、不搜尋隱藏路徑。畫面只在記憶體顯示，不存檔、不上傳；離開頁面或進背景即停止並清除畫面。需要登入、HTTPS、其他格式、離線或網路隔離的設備可能無法確認。")
            }
        }.navigationTitle("拍攝來源驗證").navigationBarTitleDisplayMode(.inline)
            .onDisappear { verifier.stop(clearImage: true) }
            .onChange(of: scenePhase) { if $0 == .background { verifier.stop(clearImage: true) } }
    }
}
