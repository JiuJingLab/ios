# 揪鏡 Logo

`jiujing-logo.png` 是使用者於 2026-09-30 提供的原始 Logo 素材，尺寸為 1024 × 1024。保留深綠底、白色盾牌／鏡頭、綠色斜線與星芒，以及原圖的透明圓角。README、填表頁及網頁圖示直接引用此檔。

在專案根目錄執行 `swift scripts/make-icon.swift`，由同一原圖產生：

- `JiuJing/Assets.xcassets/AppIcon.appiconset/AppIcon.png`：1024 × 1024，以原圖底色 `#0F3D3E` 補滿透明圓角、不含透明通道，供 iPhone、iPad 與 App Store 圖示使用。
- `JiuJing/Assets.xcassets/BrandLogo.imageset/BrandLogo.png`：256 × 256，保留透明圓角，供 App 內品牌標誌使用。

未來更換 Logo 時，替換原圖並重新執行腳本。介面中的 Wi-Fi、藍牙與掃描按鈕圖示屬於功能符號，維持其操作含義。
