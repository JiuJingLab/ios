# v0.3 驗證紀錄

分支 `codex/feat/v0.3`，App 0.3.0 / build 3。新增五項本機輔助工具與拍攝來源驗證；目前沒有真實攝影機辨識的敏感度、特異度或誤報率數據。

## 自動化驗證

2026-09-30，以 Xcode 26.6／iOS 26.5 Simulator（iPhone 17）驗證：**34 項單元測試及 12 項 UI 測試通過；1 項實體相機測試在模擬器略過。** 完整回歸中的 11 項既有 UI 案例通過；新增驗證頁的 UI 案例修正鍵盤收起及開關點擊後，連同全套單元測試重跑通過，目前無未解決的測試失敗。generic iOS Release 無簽章建置通過。另已通過 plist 格式、archive 腳本語法與 `git diff --check` 檢查，並人工檢視新增 MAC／Wi-Fi、相機分析及音訊頁面的模擬器截圖。

```bash
xcodebuild -project JiuJing.xcodeproj -scheme JiuJing -destination 'platform=iOS Simulator,name=iPhone 17' test CODE_SIGNING_ALLOWED=NO
xcodebuild -project JiuJing.xcodeproj -scheme JiuJing -configuration Release -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
bash -n scripts/archive.sh
plutil -lint JiuJing/Info.plist JiuJing/JiuJing.entitlements JiuJing/Resources/PrivacyInfo.xcprivacy
git diff --check
```

沒有設定獨立 lint 工具；不宣稱已執行 SwiftLint。上述合成資料與模擬器測試不代表已完成真實光源、麥克風、Wi-Fi 權限或偵測準確率驗收。

- 單元：MAC 格式／隨機位址／IEEE 名單、SSID／RSSI 校驗、明暗畫面／亮點群組、真實 pixel buffer delegate 與 Vision 呼叫、44.1／48 kHz 合成音 FFT、靜音／雜訊／低頻／低音量、連續頻率判定、取消後的過期回呼。
- UI：手動 MAC 與 Wi-Fi 比對、清除、相機模式切換、模擬器硬體限制、既有區網／BLE 與隱私頁回歸。
- 建置：iOS Simulator 測試及 generic iOS Release 無簽章建置；無簽章建置不驗證 provisioning profile。

## 拍攝來源驗證

新增 12 項協定／狀態測試與 1 項授權／公網位址拒絕 UI 測試已通過，使用合成 JPEG 與本機 loopback 假服務，沒有讀取真實區網裝置的畫面。其餘 11 項 UI 回歸測試也已通過。

- RTSP：有效 SDP 與 video 軌道、CSeq 不符、HTTP 冒充 RTSP、401、截斷 body、音訊軌道不能升級成影像確認。
- HTTP：close-delimited JPEG、chunked MJPEG、單 byte 分段、帶／不帶 Content-Length 的影像部分、拒絕 HTML、無效 JPEG、過大長度與重新導向。
- 存取範圍：拒絕公網／DNS／loopback／含帳密網址，以及本機、廣播、network 位址與跨子網目標；不會測試真實外部端點。
- 狀態：未授權不連線、取消不產生後續確認、逾時不能升級成成功、單張／重複／過期／停止的畫面不能解鎖現場確認。
- RTSP 僅確認服務描述；人工確認以現場動作同步為依據，不宣稱自動辨識偷拍。

## 待實機驗收（尚未執行）

| 項目 | 驗收內容 |
|---|---|
| MAC | 以有權管理路由器的已知設備清單／標籤輸入，確認廠商比對與非命中／隨機位址提示；不能將 BSSID 當作周邊設備 MAC |
| Wi-Fi | Team／App ID／profile 開通 Access WiFi Information；允許精確位置、拒絕位置、關閉精確位置、無 Wi-Fi、切換網路、逾時、背景後重試；比對 SSID／BSSID 是否與實際 AP 相符 |
| IR | 不同 iPhone／iPad 前後鏡頭，遙控器初步校驗、IR 光源及可見光對照、開關補光、暗房／強光、鏡頭切換；確認不宣稱可見 IR 或沒有攝影機 |
| 視覺 | 真實／假攝影機、玻璃、金屬、螢幕、時鐘；遠近、旋轉、橫直向、遮擋、過曝、畫面更新與耗電／溫度；記錄漏報與誤報 |
| 音訊 | 權限拒絕、10 秒完成、提前停止、電話中斷、輸入裝置切換、背景停止；用已知音源與充電器／燈具對照，檢查取樣率與頻譜，勿將數位 dBFS 當作聲壓 |
| 拍攝來源驗證 | 使用有權管理的實體攝影機，核對 RTSP 路徑與 SDP、JPEG／MJPEG 畫面、現場動作同步；401／403、不支援的格式、Wi-Fi 切換、背景斷線及清除畫面；不以 loopback 通過宣稱真機相容 |
| 隱私 | 停止／關頁／背景時相機及麥克風指示燈熄滅；無媒體檔案、無外傳；反覆啟停後仍可使用其他功能 |

## 實作邊界

- iOS 無周邊 MAC 或一般用途全部 SSID 掃描 API；本版採使用者提供的 MAC／SSID，或目前連線 SSID／BSSID。RSSI 僅接受使用者外部量測值。
- IR 輔助辨識的是孤立亮點；一般可見光會符合，IR 濾光會造成漏報。
- Vision 只分析矩形與亮點，不具攝影機語意辨識；沒有訓練或下載模型。
- FFT 只分析麥克風收到的聲學訊號；不能分析射頻／電磁洩漏，無法發現無聲攝影／錄音設備。
- 沒有伺服器部署、TestFlight 上傳或 main／production 變更。
