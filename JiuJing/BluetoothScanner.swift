import Foundation
import CoreBluetooth

@MainActor
final class BluetoothScanner: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate {
    @Published private(set) var findings: [Finding] = []
    @Published private(set) var running = false
    @Published private(set) var phase: ScanPhase = .idle
    private var startupDeadline: DispatchWorkItem?
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "掃描附近 BLE 廣播，不連線、不配對"
    private var central: CBCentralManager?
    private var timer: Timer?
    private var capped = false
    private var pending = false
    private var started: Date?
    private var rules: DetectionRules?

    override init() {
        super.init()
        #if DEBUG
        if let scenario = ScanFixture.scenario(for: .bluetooth) {
            findings = ScanFixture.findings(scenario, source: .bluetooth)
            phase = scenario == "partial" ? .partial : scenario == "failed" ? .failed : .completed
            status = "模擬測試資料；不代表實際掃描"
        }
        #endif
    }

    func start() {
        stop()
        findings = []; progress = 0; capped = false
        guard let rules = try? DetectionRules.load() else {
            phase = .failed; status = "無法讀取偵測名單，請重新安裝 App。"; return
        }
        self.rules = rules
        pending = true; running = true; phase = .scanning
        status = "正在等候藍牙；首次使用請允許權限"
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.pending else { return }
            self.fail("等候藍牙逾時，請確認權限後重新掃描。")
        }
        startupDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: deadline)
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if let central { centralManagerDidUpdateState(central) }
    }
    func stop() {
        let wasRunning = running
        startupDeadline?.cancel(); startupDeadline = nil
        pending = false; running = false
        central?.stopScan(); timer?.invalidate(); timer = nil; started = nil
        if wasRunning { phase = .partial; status = "已停止，顯示部分結果；可重新掃描。" }
    }
    func clear() { stop(); findings = []; progress = 0; phase = .idle; status = "結果已清除" }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard pending || running else { return }
        switch central.state {
        case .poweredOn:
            guard pending else { return }
            pending = false
            startupDeadline?.cancel(); startupDeadline = nil
            status = "掃描中 · 20 秒；訊號強弱不等於距離"
            started = Date()
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let started = self.started else { return }
                    self.progress = min(1, Date().timeIntervalSince(started) / 20)
                    if self.progress >= 1 {
                        self.stop()
                        self.phase = self.capped ? .partial : .completed
                        self.status = self.capped ? "已達 500 個裝置上限；本輪僅顯示部分結果。" : "本輪掃描結束。僅能顯示正在廣播的 BLE 裝置，不能排除偷拍設備。"
                    }
                }
            }
        case .unauthorized: fail("藍牙權限未允許，請在設定中開啟後重試。")
        case .poweredOff: fail("藍牙已關閉，請在系統設定開啟藍牙。")
        case .unsupported: fail("此裝置不支援 BLE 掃描；模擬器請改用實機。")
        case .resetting: fail("藍牙服務正在重設，請稍後重試。")
        case .unknown: status = "等待系統回報藍牙狀態"
        @unknown default: fail("目前無法使用藍牙，請稍後重試。")
        }
    }
    private func fail(_ message: String) { stop(); phase = .failed; status = message }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard running, !pending else { return }
        let id = peripheral.identifier.uuidString
        let old = findings.first { $0.id == id }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? old?.name ?? "未提供名稱的藍牙裝置"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let finding = Finding(id: id, name: name, source: .bluetooth, address: id, services: Set(services).union(old?.services ?? []), rssi: RSSI.intValue == 127 ? nil : RSSI.intValue, reasons: rules?.reasons(name: name) ?? [])
        if let index = findings.firstIndex(where: { $0.id == id }) { findings[index] = finding }
        else if findings.count < 500 { findings.append(finding) }
        else { capped = true; status = "已達 500 個裝置上限；目前結果不完整。" }
    }
}
