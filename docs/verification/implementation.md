# 影片版與閱讀風格改版驗證

日期：2026-10-23。

## 實作範圍

- 真實三刊公開目錄與供應商清單，台北近四日日期映射，播放前刷新滾動集號。
- 閱讀風格首頁與獨立播放頁；三刊切換、日期選擇、來源狀態、官方文章入口與偏好。
- LINE TV 官方播放器、YouTube 官方嵌入與實際安裝 App ID 的 Referer。
- 全螢幕保留同一份 WebView 文件；返回、離頁停止及跨頁方向序列。
- 原創書頁／播放 Icon，以及 iOS、Android、macOS 圖示尺寸。

## 變更檔案群組

- `lib/main.dart`、`lib/features/library/library_page.dart`、`lib/preferences.dart`：介面、互動與偏好。
- `lib/domain/lesson.dart`、`lib/data/lesson_repository.dart`：資料模型、來源解析與日期核對。
- `lib/features/media/player_page.dart`：官方嵌入、全螢幕與播放生命週期。
- `assets/branding/`、`tool/generate_icons.swift`、各平台 AppIcon／mipmap：原創圖示及可重建來源。
- `pubspec.yaml`／lock、Android manifest／最低 SDK、iOS 最低版本與模擬器設定、macOS 網路權限：平台支援。
- `test/`、`integration_test/`、`test_driver/`、`tool/check_sources.dart`：離線測試及選用真實來源檢查。

## 簡化

移除計數器範例與大型宣傳卡；未建立後端或額外狀態管理框架。影片使用官方播放器，不加入自製串流、影片下載、會員帳密或音訊抽取。公開資料快取只存在記憶體，偏好使用本機儲存。

## 已驗證與限制

- 靜態分析與 21 項離線單元／widget 測試通過。
- 真實來源檢查：三刊 12 個日期主題與目前列出的 9 支免費影片匹配；第四日未列出影片。
- iOS 模擬器：三刊官方文件載入、全螢幕橫向、退出後直向、同一文件未重新載入，均通過。
- iOS 19 個與 macOS 10 個 AppIcon 項目的尺寸及不透明 RGB 格式、Android 5 種密度尺寸通過檢查。
- 影片解碼、音訊、地區與逐集可用性仍依官方播放器；預設原生測試不宣稱已驗證全部節目串流。
- Android APK 可建置；本機 API 36.1 模擬器曾發生系統服務崩潰，尚未取得可靠的 Android 原生串流驗證。未將該環境故障宣稱為產品功能通過。
- 使用者已回報能以現有 `build_app.sh` 選項 8 安裝至 iPhone 13。本次未修改或執行該外部腳本，也未變更手機簽章設定。
- 未加入會員全文／獨立廣播整合、持久化離線索引或可靠歷史月份來源；跨月未確認狀態仍保留。

## 圖像

首頁：`library-ios.png`。播放頁：`lt-player-ios.png`、`sc-player-ios.png`、`ad-player-ios.png`。原創 Icon：`../../assets/branding/app-icon.png`。
