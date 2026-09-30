import SwiftUI
import CoreLocation
import NetworkExtension

struct MACAddress: Equatable {
    let bytes: [UInt8]
    init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: text.contains(":") ? ":" : "-", omittingEmptySubsequences: false)
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6, bytes.contains(where: { $0 != 0 }), bytes[0] & 1 == 0 else { return nil }
        self.bytes = bytes
    }
    var prefix: String { bytes.prefix(3).map { String(format: "%02X", $0) }.joined() }
    var isLocal: Bool { bytes[0] & 2 != 0 }
}

struct OUIRules: Decodable {
    struct Entry: Decodable { let prefix: String; let organization: String }
    let source: String
    let retrieved: String
    let entries: [Entry]

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "camera_oui", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        let rules = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard !rules.entries.isEmpty, Set(rules.entries.map(\.prefix)).count == rules.entries.count,
              rules.entries.allSatisfy({ $0.prefix.count == 6 && $0.prefix.allSatisfy(\.isHexDigit) && !$0.organization.isEmpty }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return rules
    }
    func result(for text: String) -> String {
        guard let address = MACAddress(text) else { return "格式無效。請輸入六組十六進位，例如 00:11:22:33:44:55；不接受全零或群播位址。" }
        guard !address.isLocal else { return "這是本地管理／可能隨機化的位址，無法可靠比對廠商。" }
        guard let entry = entries.first(where: { $0.prefix == address.prefix }) else {
            return "未命中這份有限的攝影設備廠商 OUI 名單；不代表沒有攝影機。"
        }
        return "前綴登記廠商：\(entry.organization)。該廠商也製造其他設備；OUI 可偽造，不能判斷型號、用途或是否偷拍。"
    }
}

struct WiFiAssessment {
    static func result(ssid: String, rssi: String, rules: DetectionRules) -> String {
        let name = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 32 else { return "請輸入 1–32 bytes 的 SSID。" }
        let signal = rssi.trimmingCharacters(in: .whitespacesAndNewlines)
        if !signal.isEmpty, Int(signal).map({ (-127 ... -1).contains($0) }) != true {
            return "RSSI 請填 -127 到 -1 dBm 的整數，或留白。"
        }
        var result = rules.reasons(name: name)
        if result.isEmpty { result.append("SSID 未命中名稱規則；名稱可以更改，不能排除攝影機。") }
        if let value = Int(signal) {
            let strength = value >= -50 ? "較強" : value >= -70 ? "中等" : "較弱"
            result.append("你輸入的訊號為 \(value) dBm（\(strength)）。訊號強弱不代表距離或設備類型，不作為可疑判定依據。")
        }
        return result.joined(separator: "\n\n")
    }
}

@MainActor
final class CurrentWiFi: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var ssid = ""
    @Published private(set) var bssid = ""
    @Published private(set) var message = "可手動輸入，或授權讀取目前連線的 Wi-Fi。"
    @Published private(set) var loading = false
    private let location = CLLocationManager()
    private var generation = UUID()
    private var timeout: Task<Void, Never>?

    override init() { super.init(); location.delegate = self }
    func read() {
        cancel()
        ssid = ""; bssid = ""; loading = true
        message = "等待 Wi-Fi 資訊或位置授權…"
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, self.loading else { return }
            self.cancel(); self.message = "讀取逾時，請重試或手動輸入 SSID。"
        }
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
        else { fetchIfAuthorized() }
    }
    func cancel() { generation = UUID(); timeout?.cancel(); timeout = nil; loading = false }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.loading, self.location.authorizationStatus != .notDetermined else { return }
            self.fetchIfAuthorized()
        }
    }
    private func fetchIfAuthorized() {
        guard location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways,
              location.accuracyAuthorization == .fullAccuracy else {
            cancel(); message = "需要使用 App 期間的精確位置授權才能讀取 SSID；仍可手動輸入。不會取得 GPS 座標。"; return
        }
        let token = generation
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            Task { @MainActor in
                guard let self, self.loading, self.generation == token else { return }
                self.cancel()
                guard let network else {
                    self.message = "無法取得目前 Wi-Fi。請確認已連線、精確位置權限與 App 的 Access WiFi Information 簽章能力，或手動輸入。"; return
                }
                self.ssid = network.ssid; self.bssid = network.bssid
                self.message = "已讀取目前連線。BSSID 是存取點位址，不是附近裝置清單。iOS 此 API 不提供 RSSI。"
            }
        }
    }
}

struct NetworkCluesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var wifi = CurrentWiFi()
    @State private var mac = ""
    @State private var ssid = ""
    @State private var rssi = ""
    @State private var macResult = ""
    @State private var wifiResult = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("MAC 位址名單比對") {
                    Text("從有權管理的路由器清單或設備標籤輸入 MAC。iOS 無法自動讀取周邊裝置 MAC；BLE UUID 不能用於比對。")
                    TextField("MAC 位址", text: $mac).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("macInput")
                        .onChange(of: mac) { _ in macResult = "" }
                    Button("比對 MAC 名單") {
                        do { macResult = try OUIRules.load().result(for: mac) }
                        catch { macResult = "名單缺少或損毀，無法比對。" }
                    }.accessibilityIdentifier("matchMAC")
                    if !macResult.isEmpty { Text(macResult).accessibilityIdentifier("macResult") }
                    Text("使用 IEEE MA-L 登記資料中的部分影像設備廠商前綴；不是偷拍裝置黑名單。來源與日期見專案 README。 ").font(.footnote)
                }
                Section("Wi-Fi 名稱與訊號檢查") {
                    Text("只讀取目前連線，無法列出周邊 SSID。可從系統 Wi-Fi 頁面手動輸入名稱；RSSI 僅能從你有權使用的路由器或量測工具取得，沒有資料請留白。")
                    Button(wifi.loading ? "讀取中…" : "讀取目前 Wi-Fi") { wifi.read() }.disabled(wifi.loading)
                    Text(wifi.message).font(.footnote)
                    if !wifi.bssid.isEmpty {
                        Text("存取點 BSSID：\(wifi.bssid)").font(.footnote.monospaced())
                        Button("將存取點 BSSID 帶入 MAC 比對") { mac = wifi.bssid; macResult = "" }
                    }
                    TextField("SSID", text: $ssid).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("ssidInput")
                        .onChange(of: ssid) { _ in wifiResult = "" }
                    TextField("RSSI（選填，dBm）", text: $rssi).keyboardType(.numbersAndPunctuation)
                        .onChange(of: rssi) { _ in wifiResult = "" }
                    Button("檢查 Wi-Fi 線索") {
                        do { wifiResult = WiFiAssessment.result(ssid: ssid, rssi: rssi, rules: try DetectionRules.load()) }
                        catch { wifiResult = "名稱規則缺少或損毀，無法比對。" }
                    }.accessibilityIdentifier("matchWiFi")
                    if !wifiResult.isEmpty { Text(wifiResult).accessibilityIdentifier("wifiResult") }
                }
                Section {
                    Button("清除輸入與結果") { wifi.cancel(); ssid = ""; rssi = ""; mac = ""; macResult = ""; wifiResult = ""; wifi.clear() }
                    Button("開啟系統設定") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                }
            }.navigationTitle("MAC 與 Wi-Fi").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完成") { dismiss() } }
                .onChange(of: wifi.ssid) { value in if !value.isEmpty { ssid = value } }
                .onDisappear { wifi.cancel() }
                .onChange(of: scenePhase) { if $0 == .background { wifi.cancel() } }
        }
    }
}

extension CurrentWiFi {
    func clear() { cancel(); ssid = ""; bssid = ""; message = "資料已清除。" }
}
