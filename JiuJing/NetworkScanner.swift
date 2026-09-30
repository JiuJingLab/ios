import Foundation
import Network
import Darwin

@MainActor
final class NetworkScanner: ObservableObject {
    @Published private(set) var findings: [Finding] = []
    @Published private(set) var running = false
    @Published private(set) var phase: ScanPhase = .idle
    private var limitedCoverage = false
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "連上要檢查的 Wi-Fi 後開始"
    @Published private(set) var coverage = "IPv4 常見端口與 Bonjour 服務"
    private var monitor: NWPathMonitor?
    private var browsers: [NWBrowser] = []
    private var probes: [UUID: TCPProbe] = [:]
    private var jobs: [(String, UInt16)] = []
    private var cursor = 0
    private var completed = 0
    private var generation = UUID()
    private var deadline: DispatchWorkItem?
    private var rules: DetectionRules?
    private var selectedInterface: String?
    private var selectedSubnet: String?

    init() {
        #if DEBUG
        if let scenario = ScanFixture.scenario(for: .network) {
            findings = ScanFixture.findings(scenario, source: .network)
            phase = scenario == "partial" ? .partial : scenario == "failed" ? .failed : .completed
            status = "模擬測試資料；不代表實際掃描"
        }
        #endif
    }

    func start() {
        stop()
        findings = []
        progress = 0
        limitedCoverage = false
        coverage = "正在確認可檢查的網路範圍"
        guard let rules = try? DetectionRules.load() else {
            phase = .failed; status = "無法讀取偵測名單，請重新安裝 App。"; return
        }
        self.rules = rules
        running = true
        phase = .scanning
        status = "正在確認 Wi-Fi；首次使用請允許本機網路權限"
        let token = generation
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self, self.generation == token, self.running else { return }
                guard path.status == .satisfied else {
                    self.finish("未連上可用的 Wi-Fi，掃描未完成。"); return
                }
                let names = Set(path.availableInterfaces.filter { $0.type == .wifi }.map(\.name))
                guard let (subnet, interface) = Self.wifiSubnet(names: names) else {
                    self.finish("此 Wi-Fi 沒有可用的 IPv4 位址；v0.2 無法掃描此網路。"); return
                }
                if let previous = self.selectedSubnet {
                    if previous != subnet.label || self.selectedInterface != interface {
                        self.finish("Wi-Fi 已改變，掃描已停止；請重新開始。", phase: .partial)
                    }
                    return
                }
                self.limitedCoverage = subnet.isPartial
                self.selectedInterface = interface
                self.selectedSubnet = subnet.label
                self.coverage = "\(subnet.label) · \(subnet.hosts.count) 個位址 · \(rules.ports.count) 個端口" + (subnet.isPartial ? "（僅手機所在 /24 範圍）" : "")
                self.jobs = subnet.hosts.flatMap { host in rules.ports.map { (host, $0) } }
                self.status = "掃描中；只檢查服務是否接受連線"
                self.browse(token: token)
                self.pump(token: token)
            }
        }
        monitor.start(queue: .main)
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.running else { return }
            self.finish("掃描逾時，結果可能不完整。確認網路權限後再試。", phase: .partial)
        }
        self.deadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: deadline)
    }

    func stop() {
        let wasRunning = running
        generation = UUID()
        running = false
        deadline?.cancel(); deadline = nil
        monitor?.cancel(); monitor = nil
        browsers.forEach { $0.cancel() }; browsers = []
        let active = Array(probes.values)
        probes.removeAll()
        active.forEach { $0.cancel() }
        jobs = []; cursor = 0; completed = 0
        selectedInterface = nil; selectedSubnet = nil
        if wasRunning { phase = .partial; status = "已停止，顯示部分結果；可重新掃描。" }
    }

    func clear() { stop(); findings = []; progress = 0; phase = .idle; status = "結果已清除"; coverage = "IPv4 常見端口與 Bonjour 服務" }

    private func finish(_ message: String, phase: ScanPhase = .failed) { stop(); self.phase = phase; status = message }

    private func browse(token: UUID) {
        for type in ["_rtsp._tcp", "_http._tcp", "_axis-video._tcp"] {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .wifi
            parameters.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: parameters)
            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.running, self.generation == token else { return }
                    if case .waiting(let error) = state, case .dns(let code) = error, code == -65570 {
                        self.finish("本機網路權限未允許。請到設定開啟後重新掃描。")
                    }
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    guard let self, self.running, self.generation == token else { return }
                    for result in results {
                        guard case .service(let name, let serviceType, let domain, _) = result.endpoint else { continue }
                        let id = "bonjour:\(name):\(domain)"
                        var finding = self.findings.first { $0.id == id } ?? Finding(id: id, name: name, source: .network, address: "Bonjour 服務 · \(domain)")
                        finding.services.insert(serviceType)
                        self.upsert(finding)
                    }
                }
            }
            browsers.append(browser)
            browser.start(queue: .main)
        }
    }

    private func pump(token: UUID) {
        guard running, generation == token else { return }
        while probes.count < 40 && cursor < jobs.count {
            let (host, port) = jobs[cursor]
            cursor += 1
            let id = UUID()
            let probe = TCPProbe(host: host, port: port, interface: selectedInterface) { [weak self] result in
                guard let self, self.running, self.generation == token else { return }
                self.probes[id] = nil
                if result == .denied {
                    self.finish("本機網路存取遭拒，掃描未完成。請到設定允許後再試。")
                    return
                }
                if result == .open {
                    var finding = self.findings.first { $0.id == host } ?? Finding(id: host, name: "網路裝置", source: .network, address: host)
                    finding.ports.insert(port)
                    self.upsert(finding)
                }
                self.completed += 1
                self.progress = Double(self.completed) / Double(max(1, self.jobs.count))
                self.pump(token: token)
            }
            probes[id] = probe
            probe.start()
        }
        if cursor == jobs.count && probes.isEmpty {
            // Keep Bonjour discovery alive for a minimum discovery window on tiny networks.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.running, self.generation == token else { return }
                self.progress = 1
                self.finish(self.limitedCoverage ? "本輪僅檢查部分網段；其他範圍尚未檢查。" : "本輪掃描結束。被隔離、逾時或未回應的裝置可能無法顯示。", phase: self.limitedCoverage ? .partial : .completed)
            }
        }
    }

    private func upsert(_ value: Finding) {
        var value = value
        value.reasons = rules?.reasons(name: value.name, ports: value.ports, services: value.services) ?? []
        if let index = findings.firstIndex(where: { $0.id == value.id }) { findings[index] = value }
        else { findings.append(value) }
    }

    static func wifiSubnet(names: Set<String>) -> (IPv4Subnet, String)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var item = list
        while let pointer = item {
            let entry = pointer.pointee
            item = entry.ifa_next
            let name = String(cString: entry.ifa_name)
            guard names.contains(name), entry.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = entry.ifa_addr, let mask = entry.ifa_netmask,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            func string(_ value: UnsafeMutablePointer<sockaddr>) -> String {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(value, socklen_t(value.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return "" }
                return String(cString: buffer)
            }
            if let subnet = IPv4Subnet(address: string(address), mask: string(mask)) { return (subnet, name) }
        }
        return nil
    }
}

// All callbacks are serialized on the main queue, including cancellation and timeout.
final class TCPProbe {
    enum Result { case open, closed, denied }
    private let connection: NWConnection
    private var completion: ((Result) -> Void)?
    private var timeout: DispatchWorkItem?
    init(host: String, port: UInt16, interface: String? = nil, completion: @escaping (Result) -> Void) {
        let parameters = NWParameters.tcp
        if interface != nil { parameters.requiredInterfaceType = .wifi }
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        self.completion = completion
    }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.finish(.open)
            case .failed: self.finish(.closed)
            case .waiting:
                if self.connection.currentPath?.unsatisfiedReason == .localNetworkDenied { self.finish(.denied) }
            default: break
            }
        }
        let timer = DispatchWorkItem { [weak self] in self?.finish(.closed) }
        timeout = timer
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: timer)
    }
    func cancel() { completion = nil; timeout?.cancel(); connection.stateUpdateHandler = nil; connection.cancel() }
    private func finish(_ result: Result) {
        guard let callback = completion else { return }
        cancel()
        callback(result)
    }
}
