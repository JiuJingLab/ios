# v0.1 驗證紀錄

日期：2026-09-29。環境：Xcode 26.6（17F113）、iOS Simulator 26.5、iPhone 17 Pro。

| 驗證 | 結果 |
|---|---|
| Simulator 編譯 | 通過 |
| XCTest 核心測試 | 9 項通過、0 失敗：名單載入、非攝影機服務判讀、網段邊界及輸入驗證、停止／清除、localhost 真實 TCP listener、取消回呼 |
| XCUITest | 2 項通過、0 失敗：同意前停用、模式切換、隱私與指引可達 |
| Release iOS archive（未簽署） | 通過；`build/JiuJing-unsigned.xcarchive` 僅供建置驗證，不能上傳或安裝 |
| 自動簽署 archive | 失敗：Xcode `No Accounts`，且無 `org.jiujinglab.ios` matching provisioning profile |
| TestFlight build | 尚未上傳，沒有可供測試的 TestFlight 連結 |
| 真實 iPhone BLE／LAN／權限 | 尚未執行；本機列出的 iPhone 為 unavailable |
| 報名資料 | 痛點 36 字、理念 251 字、21 欄；表格可開啟、複製按鈕有回饋及手動選取備援 |
| 影片／報名送出 | 劇本完成；未錄製影片、未上傳 YouTube、未正式送出報名 |

完整 11 項測試結果位於 `build/FinalTests.xcresult`；乾淨模擬器的介面驗證位於 `build/CleanUI.xcresult`，Bonjour 大小寫／尾點正規化的最後核心驗證位於 `build/FinalCore.xcresult`。該檔與原始 QA 截圖只留在本機，不提交：模擬器可能帶有既有帳號的系統提示。

不需要 App Intents 的本專案會出現 Xcode「Metadata extraction skipped. No AppIntents.framework dependency found.」工具提示；編譯、連結及測試均通過。沒有用 npm／pip／Cargo 依賴，未執行不適用的 package audit。

須完成 `device-validation.md` 的實機項目，才能宣稱已驗證真實硬體偵測。App 尚未經 Apple Beta App Review 或 App Store Review。
