# v0.2 畫面驗證

2026-09-30，以 iPhone 17 Pro／iOS 26.5 Simulator 執行 XCTest 產生。這些結果是 `DEBUG` 模擬資料，畫面明確標示，不是偵測準確率或真實裝置證據。

- `network-*.png`、`bluetooth-*.png`：待確認、未命中、部分結果與失敗。
- `large-type-dark.png`：accessibility3 字級與深色模式，文字換行可讀，待確認入口可捲動操作。
- `camera-unavailable.png`：模擬器不支援相機時的說明；紅外線指引開合已測試。
- `ipad-review.png`：iPad Pro 13 吋結果總覽。

測試資料與啟動參數只存在 Debug，不會進入 TestFlight Release。硬體測試沒有擷取、保存或上傳相機影像。
