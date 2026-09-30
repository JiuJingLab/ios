# JiuJing 揪鏡 · v0.3 開發版

<img src="docs/brand/jiujing-logo.png" alt="揪鏡 Logo" width="128" height="128">

> 免費、開源、可信任的公益反偷拍工具
> A free, open-source, trustworthy anti-hidden-camera tool — built as a public good.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release: v0.2](https://img.shields.io/badge/release-v0.2-green)](https://github.com/JiuJingLab/ios/releases/tag/v0.2)
[![Platform](https://img.shields.io/badge/platform-iOS%2016%2B-blue)]()
[![Code of Conduct](https://img.shields.io/badge/Code%20of%20Conduct-v1.0-ff69b4)](https://github.com/JiuJingLab/Code-of-Conduct)

**不應該只有偷拍工具。這世界也應該有免費、可信任的公益反偷拍工具。**

## TestFlight v0.2 已上架・申請內測

**v0.2（App `0.2.0`、build `2`）已上架 TestFlight，提供受邀測試者安裝。** v0.3 為開發中的版本，尚未上架 TestFlight。

- [申請內測：填寫 Google Form](https://docs.google.com/forms/d/e/1FAIpQLSdzdQjYGL6-Jmyyk6onOKuoExmuiD8OD0J5rv0c4Ipi3wgdlA/viewform)
- [下載 TestFlight App](https://apps.apple.com/tw/app/testflight/id899247664)
- [TestFlight v0.2 建置頁（需 App Store Connect 管理權限）](https://appstoreconnect.apple.com/apps/6817397936/testflight/ios/0ff53bb7-61e6-4734-9d05-2d3f35144c2c)

目前採邀請制，填表後將依名額與版本進度分批寄送 Email 測試邀請；請透過邀請在 TestFlight 安裝揪鏡。上方建置頁是管理連結，不是公開安裝連結；填表不代表立即取得測試資格。

## 影片介紹

[![觀看揪鏡介紹影片：還給使用者一個乾淨、無偷拍、私密的安全空間](https://i.ytimg.com/vi/lftKUIdO3tI/hqdefault.jpg)](https://youtube.com/shorts/lftKUIdO3tI?si=zCjGtetUNFP0gS71)

[▶ 點擊縮圖，在 YouTube 觀看揪鏡介紹影片](https://youtube.com/shorts/lftKUIdO3tI?si=zCjGtetUNFP0gS71)

---

## 名稱由來

把藏在暗處的**鏡**頭**揪**出來，還給使用者一個乾淨、無偷拍、私密的安全空間。

維護團隊：**JiuJing Lab 揪鏡實驗室**

---

## 為什麼做揪鏡

### 1. 偷拍已經不是個案

2026 年 5 月起，台灣醫美診所針孔偷拍事件接連爆發。截至 5 月 28 日，衛福部稽查 1,090 家醫療機構，累計 41 家違規遭罰（多數處 50 萬元罰鍰並停業 6 個月）；受害者自救會人數超過千人，其中包含未成年人。攝影機被藏在天花板的「煙霧偵測器」裡——一般人根本無從辨識。

### 2. 反偷拍工具應該是公共財

保護自己不被偷拍，不該是付費才能擁有的能力。揪鏡**永久免費**。

### 3. 偵測資料留在手機

v0.3 的區網／BLE、MAC／Wi-Fi 比對、相機逐幀分析與音訊頻譜都在手機端執行。沒有帳號、伺服器或分析 SDK，不上傳掃描結果、影像或聲音。程式碼與限制公開，讓使用者可以查證資料處理方式。

### 4. 開源，才能跟上偷拍的速度

用資安攻防來比喻：**偷拍是紅隊，反偷拍是藍隊。** 紅隊的技術不斷推陳出新，也會研究藍隊的防禦手法。藍隊如果不能快速迭代，防禦就失去意義。

---

## 為什麼開源

1. **專案不依賴特定人**：即使核心成員暫時不在，社群仍能讓專案正常運作。
2. **跟上紅隊的節奏**：社群定期舉辦技術研究讀書會，追蹤新型偷拍手法、討論防禦策略，持續提升產品的防禦能力。

**我們不怕被抄，也不太怕被紅隊研究。** 公益產品開源行之有年。比起防禦手法被看見，我們更怕的是閉門造車、技術遠遠落後。開源社群的多人關注與討論，正是解決這個問題的方法。

---

## 偵測技術與 v0.3 進度

開發分支：[`codex/feat/v0.3`](https://github.com/JiuJingLab/ios/tree/codex/feat/v0.3)，App `0.3.0`、build `3`。**v0.2 已上架 TestFlight；v0.3 尚未上架，新增功能待實機驗收與效能／誤報評估。** 下表的「已實作」表示有可操作流程與程式碼，不表示已驗證能辨識偷拍設備。

| # | 技術 | 實作內容與邊界 | 運算位置 | 進度 |
|---|---|---|---|---|
| 1 | 區網掃描 | 同 Wi-Fi 的 IPv4 常用 TCP 端口與 Bonjour；不取得周邊 MAC | 手機端 | v0.1／v0.2 已實作；iPhone 15 實機實測通過 |
| 2 | 藍牙 BLE | 被動廣播、名稱規則與 RSSI；不連線、不配對 | 手機端 | v0.1／v0.2 已實作；iPhone 15 實機實測通過 |
| 3 | MAC 位址名單比對 | 手動輸入路由器清單／設備標籤的 MAC，或帶入目前存取點 BSSID；比對 IEEE 廠商 OUI；拒絕群播、全零與無效格式，本地／隨機位址不推測廠商 | 手機端 | v0.3 已實作有限名單比對；iOS 周邊 MAC 自動取得不支援 |
| 4 | Wi-Fi | 讀取目前 SSID／BSSID，或手動輸入 SSID 比對名稱；可選填外部量測 RSSI，強度不參與可疑判定 | 手機端 | v0.3 已實作；目前連線讀取待實機驗收；全部 SSID／RSSI 自動掃描不支援 |
| 5 | 紅外線 | 相機逐幀尋找暗背景孤立亮點，提供遙控器校驗提示與前後鏡頭切換；無法分辨可見光與 IR，也不能量測波長 | 手機端 | v0.3 已實作實驗性亮點輔助；非專用 IR 偵測，待實機驗收 |
| 6 | 即時視覺 | 每秒最多 2 幀，偵測孤立反光與含亮點的 Vision 矩形輪廓，顯示線索數量；非攝影機物件辨識模型 | 手機端 | v0.3 已實作實驗性幾何分析；待實機驗收與準確率評估 |
| 7 | 音訊 | 使用者啟動 10 秒麥克風分析，Hann window＋2048 點 FFT、8 頻帶、窄帶音持續性提示；不偵測電磁訊號，不具有攝影／錄音器專屬聲紋 | 手機端 | v0.3 已實作實驗性聲學分析；待實機驗收與準確率評估 |

**註：未來計劃購買紅隊設備（實體偷拍機），作為藍隊反偷拍工具的實驗測試用。** 前兩項已完成 iPhone 15 的實機功能測試；針對實體偷拍機的命中率、漏報率與誤報率，將另行驗證。

原規劃的伺服器影像／音訊辨識尚未建置；本版先提供上述可在手機獨立運行的實驗性分析，無上傳端點、模型服務或帳號需求。所有結果僅是人工複查線索，不可用來確認或排除偷拍。

### 五項新增功能如何使用

- **MAC**：首頁「MAC 名單與 Wi-Fi 線索」輸入 MAC，再按「比對 MAC 名單」。內建 [121 筆 MA-L 前綴](JiuJing/Resources/camera_oui.json)，從 [IEEE 公開資料](https://standards-oui.ieee.org/oui/oui.csv)於 2026-09-30 擷取 Axis Communications、Hangzhou Hikvision、Zhejiang Dahua 登記項目。不是完整 IEEE 名單或偷拍黑名單；不涵蓋 MA-M／MA-S，廠商也可能製造其他設備。
- **Wi-Fi**：同頁可手動輸入名稱，或按「讀取目前 Wi-Fi」。後者需要精確位置授權與 `Access WiFi Information` entitlement；沒有呼叫 GPS 座標更新。拒絕、逾時或未連線時仍可手動輸入。依 [Apple fetchCurrent 文件](https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent(completionhandler:))，此 API 不填入訊號強度，因此沒有將預設值冒充 RSSI；[iOS Wi-Fi API 限制](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview)也不允許一般 App 掃描所有附近網路。
- **紅外線**：進入「相機輔助檢查」，選「紅外線亮點」，啟動後先以一般遙控器確認鏡頭可見閃光，關補光、降低環境光後巡視；更換鏡頭須重新確認。手機濾光片可能完全阻擋 IR，亮點也可能只是可見光。
- **即時視覺**：同頁選「即時視覺」並啟動，查看每幀孤立亮點與含亮點矩形輪廓的數量，搭配預覽、放大與補光人工確認。玻璃、螢幕、金屬會誤報，小型、圓形或被遮蔽的設備可能完全漏掉。
- **音訊**：首頁「音訊線索」啟動 10 秒分析。顯示取樣率、理論頻率上限、dBFS（非 dB SPL）與相對頻帶能量；2–20 kHz 範圍內高於平均頻譜 18 dB、數位音量高於 -65 dBFS 且連續三次頻率接近的音調會留下提示。這些是未經實機校準的啟發式門檻；充電器、燈具、昆蟲等也會符合，無聲設備不會被發現。

新增的相機與音訊取樣只在記憶體即時處理，不保存原始媒體；離開頁面或進背景會停止，返回前景不會自動重啟。權限按功能啟動時才要求，手動 MAC／SSID 比對不要求權限。

驗證：22 項單元測試與 11 項 UI 測試通過，1 項實機相機測試在模擬器略過；iOS Release 無簽章建置通過。詳細方式、結果與待實機項目見 [v0.3 驗證紀錄](docs/validation-v0.3.md)。

## v0.2 已發佈實作範圍（歷史紀錄）

版本：[v0.2](https://github.com/JiuJingLab/ios/releases/tag/v0.2)，App `0.2.0`，build `2`。**已上架 TestFlight，提供受邀測試者安裝**；可透過上方 Google Form 申請內測，詳細發佈紀錄見[發佈文件](docs/testflight.md)。

- SwiftUI 原生介面，iPhone／iPad、iOS 16+；沿用核定的 JiuJing 揪鏡 Logo。
- **更清楚的掃描結果**：頂部大型狀態卡、待確認／總紀錄數、警示圖示、醒目外框、命中原因、直接查看待確認線索；支援深色模式與 VoiceOver 提醒。
- 明確區分尚未開始、掃描中、已完成、部分結果與失敗。中途停止、逾時、網段受限或權限失敗不會被呈現成「本輪未發現可疑線索」。
- 區網：TCP 80、443、554、8554、8000、8080；Bonjour `_rtsp._tcp`、`_http._tcp`、`_axis-video._tcp`。
- BLE：20 秒被動廣播探索、名稱規則、RSSI、去重；不連線、不配對。等待藍牙超過 15 秒會提示重試。
- **相機輔助檢查**：使用者手動啟動的本機即時預覽、最高 4× 放大（依鏡頭能力）、補光及前後鏡頭切換。沒有拍照、錄影、儲存、上傳或自動 AI 判定。
- **紅外線檢查指引**：說明如何用一般電視遙控器初步觀察鏡頭反應及其限制；不是紅外線感測器，也不保證看見夜視光源。
- 無帳號、廣告、分析 SDK、伺服器、使用額度。掃描結果只在記憶體；進背景停止掃描與相機。
- 規則隨 App 提供；缺少或損毀時停止掃描並顯示錯誤。

**偵測限制：**線索不能確認或排除攝影機。一般 HTTP 服務、藍牙名稱與訊號強度都不是偷拍證據。本版未取得周邊 MAC/OUI，不猜測廠商。區網限 IPv4；大於 /24 的網路只檢查手機所在 /24（標示部分結果），最多 255 個其他位址、40 條並行連線、每個端口 0.85 秒逾時，整輪上限 60 秒。Bonjour 和 IP 紀錄可能屬於同一設備。BLE 最多保留 500 個裝置。離線攝影機、Wi-Fi 隔離、未廣播設備、VPN、防火牆與逾時均可能造成遺漏。模擬器不能驗證真實相機、BLE 或 iOS 本機網路權限。

---

## 資料與資安

以下雲端、AI 模型、帳號額度及認證內容是未來研究方向，**不是 v0.3 已提供的功能或已取得的認證**。本版只有本機規則與訊號／幾何分析；是否需要伺服器，須由模型、裝置效能與隱私評估決定。

### 設計原則

- **最小化蒐集**：只上傳偵測必要的資料，能在手機端處理的就不上傳。
- **用完即刪**：偵測完成後不保留原始影像/音訊（保存期限將於隱私政策明訂）。
- **不做其他用途**：資料不用於廣告、不販售、不提供第三方。
- **公開可查**：資料流向寫在程式碼裡，任何人都能檢驗。

### 雲端與分工

未來雲端功能可能部署於三大雲端之一（Google Cloud / AWS / Microsoft Azure，評估中）。

雲端採**責任共擔模型**：

- **雲端供應商負責**：機房實體安全、硬體、網路基礎設施，以及平台本身的資安認證。
- **揪鏡團隊負責**：應用程式、存取權限、加密設定、資料保存與刪除政策。

換句話說，選擇三大雲讓我們站在成熟的資安基礎上，但**應用層的資安仍是我們的責任**。我們規劃讓專案取得 **ISO/IEC 27001** 等資訊安全認證。

### 公信力

使用者最終會選擇自己信任的組織。揪鏡由台灣團隊開發，我們正在尋求**婦女團體及其他具公信力的公益組織**合作背書，讓這個公益產品能被信任。

---

## 營運模式

- **完全不收費**
- **開放贊助**支持伺服器成本（GCP / AWS 等）
- **合理使用額度**：為控制成本，若未來加入帳號與雲端服務，可能設定每月使用次數上限。有特殊需求（如需要頻繁檢測的個人或機構）者，歡迎來信說明，我們會個別開放。

### 長期目標

我們希望揪鏡未來能**完整移交給公益團體營運**：由公益團體承擔營運成本，JiuJing Lab 持續協助維護技術，讓專案能被長期支持、穩定運行。

---

## 快速開始

```bash
git clone https://github.com/JiuJingLab/ios.git
cd ios
git switch codex/feat/v0.3
```

需求：Xcode 26+（本次驗證版本 26.6）、iOS 16+。已提交 `JiuJing.xcodeproj`，可直接開啟；只有變更專案設定時才需要 XcodeGen 2.45+。

```bash
open JiuJing.xcodeproj
# 選擇 JiuJing scheme；實機執行時選擇自己的 Team，確認 App ID／profile 允許 Access WiFi Information。
xcodebuild -project JiuJing.xcodeproj -scheme JiuJing -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test CODE_SIGNING_ALLOWED=NO
```

若修改 `project.yml`，執行 `xcodegen generate` 重新產生專案；Team 與 Bundle ID 可在建置時覆寫，請勿提交私鑰或憑證。

- [實機驗收清單](docs/device-validation.md)
- [TestFlight 發佈與審查資料](docs/testflight.md)
- [v0.3 隱私政策](docs/privacy.md)

---

## 參與貢獻

品牌圖檔與 App 圖示的更新方式見 [Logo 素材說明](docs/brand/README.md)。

歡迎任何形式的參與：

- **補充偷拍裝置資料**：編輯 `JiuJing/Resources/known_cameras.json`，新增名稱關鍵字或端口規則，並附上來源與誤判風險
- **改善偵測功能**：協助開發、測試與驗證掃描功能
- **加入技術讀書會**：一起研究新型偷拍手法與防禦策略
- **回報誤判**：開 Issue 附上掃描截圖（請隱去個人資訊）
- **翻譯**：英文、日文、韓文

參與前請先閱讀 [社群行為準則](https://github.com/JiuJingLab/Code-of-Conduct) 與 [專案治理](https://github.com/JiuJingLab/Governance)。

---

## 法律聲明

- 本工具僅供在**自己有權使用的空間**（住家、租屋處、旅宿、診間、更衣室等）自我保護使用。
- 請勿掃描他人擁有的網路。
- 偵測結果**僅供參考**，無法保證 100% 偵測，亦不構成法律證據。**發現可疑裝置請立即報警（110）。**

---

## 授權

[MIT License](LICENSE) © JiuJing Lab 揪鏡實驗室

---

**Made in Taiwan 🇹🇼 · 守護每個人的隱私與安心**
