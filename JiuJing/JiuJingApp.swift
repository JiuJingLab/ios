import SwiftUI

@main
struct JiuJingApp: App {
    var body: some Scene { WindowGroup { HomeView() } }
}

private let forest = Color(red: 0.10, green: 0.31, blue: 0.25)
private let paper = Color(uiColor: .systemGroupedBackground)

struct HomeView: View {
    @StateObject private var network = NetworkScanner()
    @StateObject private var bluetooth = BluetoothScanner()
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode = 0
    @State private var consent = false
    @State private var showGuide = false
    @State private var showPrivacy = false

    private var running: Bool { network.running || bluetooth.running }
    private var findings: [Finding] {
        (mode == 0 ? network.findings : bluetooth.findings).sorted {
            if $0.needsReview != $1.needsReview { return $0.needsReview }
            return $0.id < $1.id
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-test-findings") {
                        Text("模擬測試資料・不代表實際偵測").font(.footnote).foregroundStyle(.orange)
                    }
                    #endif
                    hero
                    VStack(alignment: .leading, spacing: 18) {
                        Text("選擇檢查方式").font(.headline)
                        Picker("檢查方式", selection: $mode) {
                            Text("Wi-Fi 區網").tag(0)
                            Text("藍牙 BLE").tag(1)
                        }.pickerStyle(.segmented).disabled(running)
                        Label(mode == 0 ? "連接同一 Wi-Fi，探索常見服務" : "查看周圍正在廣播的 BLE 裝置", systemImage: mode == 0 ? "wifi" : "antenna.radiowaves.left.and.right")
                            .font(.subheadline)
                        Toggle(isOn: $consent) {
                            Text("我有權檢查此空間與網路").font(.subheadline)
                        }.tint(forest).disabled(running).accessibilityIdentifier("scanConsent")
                        Button {
                            if running { network.stop(); bluetooth.stop() }
                            else if mode == 0 { network.start() }
                            else { bluetooth.start() }
                        } label: {
                            HStack {
                                Image(systemName: running ? "stop.fill" : "viewfinder")
                                Text(running ? "停止掃描" : "開始檢查").fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "arrow.right")
                            }.padding(18).foregroundStyle(.white)
                                .background(consent || running ? forest : Color.gray, in: RoundedRectangle(cornerRadius: 16))
                        }.disabled(!consent && !running).accessibilityIdentifier("scanButton")
                        if running { ProgressView(value: mode == 0 ? network.progress : bluetooth.progress).tint(forest) }
                        Text(mode == 0 ? network.status : bluetooth.status)
                            .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("scanStatus")
                        if mode == 0 {
                            Text(network.coverage).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    results
                    Button { showGuide = true } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "flashlight.on.fill").font(.title2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("再多看一眼").font(.headline)
                                Text("搭配實體檢查，了解數位掃描的盲區").font(.footnote)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.padding(20).foregroundStyle(forest)
                            .background(forest.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                    }
                    HStack {
                        Text("免費 · 開源 · 掃描資料不出手機")
                        Spacer()
                        Button("隱私", action: { showPrivacy = true })
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background(paper)
                .navigationBarHidden(true)
                .sheet(isPresented: $showGuide) { GuideView() }
                .sheet(isPresented: $showPrivacy) { PrivacyView() }
                .onChange(of: scenePhase) { phase in
                    if phase == .background { network.stop(); bluetooth.stop() }
                }
        }.tint(forest)
    }
    private var header: some View {
        HStack {
            Image("BrandLogo")
                .resizable().scaledToFit().frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("揪鏡").font(.title2.bold())
                Text("JIUJING LAB").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2)
            }
            Spacer()
            Text("v0.1").font(.caption.monospaced()).foregroundStyle(forest)
                .padding(.horizontal, 12).padding(.vertical, 7).background(forest.opacity(0.08), in: Capsule())
        }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("給自己的空間，多一份留意", systemImage: "leaf").font(.caption.weight(.medium))
            Text("安心之前，\n先揪出線索。").font(.system(size: 34, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            Text("用 Wi-Fi 與藍牙探索周遭裝置，\n把值得確認的線索，交回你手中。")
                .font(.subheadline).lineSpacing(5)
            Label("沒有發現 ≠ 沒有偷拍設備", systemImage: "info.circle")
                .font(.footnote.weight(.semibold)).padding(.top, 4)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            .foregroundStyle(.white).background(forest, in: RoundedRectangle(cornerRadius: 28))
    }
    private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("本次線索").font(.title3.bold())
                Text("\(findings.count)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                if !findings.isEmpty {
                    Button("清除") { if mode == 0 { network.clear() } else { bluetooth.clear() } }
                        .font(.footnote).disabled(running)
                }
            }
            if findings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("尚無裝置線索").font(.headline)
                    Text("掃描只能看見部分裝置。離線攝影機、隔離網路與未廣播設備，可能完全不會出現。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            } else {
                Text("數量為位址／服務紀錄，同一設備可能重複出現。一般網頁服務與藍牙裝置不等於攝影機。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(findings) { finding in
                    NavigationLink { FindingView(finding: finding) } label: { FindingRow(finding: finding) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("finding-\(finding.id)")
                }
            }
        }
    }
}

struct FindingRow: View {
    let finding: Finding
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: finding.needsReview ? "exclamationmark.magnifyingglass" : "dot.radiowaves.left.and.right")
                .font(.title2).foregroundStyle(finding.needsReview ? Color.orange : forest)
            VStack(alignment: .leading, spacing: 6) {
                Text(finding.name).font(.headline).lineLimit(2)
                Text(finding.source == .network ? finding.address : "BLE 廣播 · \(finding.rssi.map { "\($0) dBm" } ?? "訊號未知")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(finding.needsReview ? "有線索，請人工確認" : "未命中規則，仍需留意")
                    .font(.caption.weight(.medium)).foregroundStyle(finding.needsReview ? Color.orange : .secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct FindingView: View {
    let finding: Finding
    var body: some View {
        List {
            Section("觀察到的資料") {
                LabeledContent("名稱", value: finding.name)
                LabeledContent("來源", value: finding.source.rawValue)
                Text(finding.address).font(.footnote.monospaced()).textSelection(.enabled)
                if !finding.ports.isEmpty { LabeledContent("開啟的 TCP 端口", value: finding.ports.sorted().map(String.init).joined(separator: ", ")) }
                if let rssi = finding.rssi { LabeledContent("訊號（非距離）", value: "\(rssi) dBm") }
                ForEach(finding.services.sorted(), id: \.self) { Text($0).font(.footnote.monospaced()) }
            }
            Section("為什麼顯示這筆線索") {
                if finding.reasons.isEmpty {
                    Text("此裝置未命中目前的名稱或影像服務規則。這不是安全認證，也不能排除攝影機。")
                }
                ForEach(finding.reasons, id: \.self) { Text($0) }
            }
            Section("下一步") {
                Text("對照空間內已知的路由器、電視或智慧家電。若設備用途不明，請向場地管理者確認，並搭配實體目視檢查。")
                Text("iOS 不提供周邊裝置的 MAC 位址，本工具不會猜測製造商。藍牙 UUID 不是 MAC 位址。")
                Text("若懷疑遭偷拍，先離開風險區域，避免拆卸或破壞設備，必要時撥打 110 求助。")
            }
        }.navigationTitle("線索詳情").navigationBarTitleDisplayMode(.inline)
    }
}

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("先保護自己") {
                    Text("若當下感到不安全，先離開空間並尋求協助，不必等掃描完成。")
                }
                Section("實體檢查清單") {
                    Label("留意朝向床鋪、更衣區與浴室的陌生物件。", systemImage: "eye")
                    Label("查看插座、時鐘、煙霧偵測器等物品是否有異常孔洞；不要自行拆卸。", systemImage: "magnifyingglass")
                    Label("向管理者確認設備用途；有疑慮時保留現場並求助。", systemImage: "person.crop.circle.badge.questionmark")
                }
                Section("v0.1 能力限制") {
                    Text("區網：僅限同一 Wi-Fi 的 IPv4、6 個常見 TCP 端口與 3 類 Bonjour 服務。大型網段只掃手機附近的 /24 範圍。訪客隔離、VPN、防火牆、逾時與權限限制都可能造成遺漏。")
                    Text("BLE：只看正在廣播的低功耗藍牙裝置。名稱可偽裝；訊號受牆面、遮蔽物與硬體影響，不代表距離。")
                    Text("不支援 MAC/OUI 讀取、全部 Wi-Fi SSID 掃描、紅外線、相機辨識或錄音分析。無法偵測只寫入記憶卡的離線攝影機。")
                    Text("結果是待確認的線索，不能證明有偷拍，也不能證明沒有偷拍。")
                }
            }.navigationTitle("多一層檢查").toolbar { Button("完成") { dismiss() } }
        }.tint(forest)
    }
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("資料留在你的手機") {
                    Text("v0.1 無帳號、廣告、分析 SDK 或雲端服務。裝置名稱、IP、端口、BLE 識別碼與訊號只在 App 記憶體中暫存；離開 App 不會持續掃描。")
                    Text("按「清除」、重新開始該類掃描，或 App 程序結束後，該次結果即清除。不寫入掃描紀錄、不上傳、不販售資料。")
                }
                Section("權限用途") {
                    Text("本機網路：探索同網路服務與 TCP 端口，不讀取影像、不登入設備。")
                    Text("藍牙：讀取廣播，不配對、不連線。不要求位置、相機或麥克風。")
                    Button("開啟系統設定") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Section("公開透明") {
                    Link("查看原始碼與回報問題", destination: URL(string: "https://github.com/JiuJingLab/ios")!)
                    Text("外部連結由你的瀏覽器開啟，適用該網站的隱私政策。")
                    Text("JiuJing Lab 揪鏡實驗室 · v0.1 · 2026-09-29").font(.footnote)
                }
            }.navigationTitle("隱私與資料").toolbar { Button("完成") { dismiss() } }
        }.tint(forest)
    }
}
