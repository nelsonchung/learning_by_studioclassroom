# 今日英語

以 Flutter 製作的三刊每日影片學習 App。資料來自空中英語教室官方公開目錄、LINE TV 與 Advanced 官方 YouTube 播放清單。

## 已實作

- 大家說英語、空中英語教室、Advanced 切換，記住上次選擇。
- 依台北時間顯示今天及前三個日曆日，App 回前景或跨日更新日期。
- 即時解析課程標題、簡介、公開文章連結及影片日期。四日索引與目前可回看的影片分別呈現。
- Android／iOS App 內使用官方播放器；全螢幕按鈕切換橫向播放，保留同一個 WebView 與播放文件，退出後返回直向。Android 返回鍵優先退出全螢幕。
- 支援 Android 官方播放器原生全螢幕回呼。離開播放頁卸載文件並復原方向與系統列。
- 播放前重新取得影片清單，避免 LINE TV 每日滾動集號造成日期錯配。
- 來源錯誤、課程未確認、免費影片未列出分開顯示；提供重新整理、重試與官方頁面備援。
- 公開目錄記憶體快取 30 分鐘；不快取影音、不抽取音訊、不整合官方會員帳密。
- 簡潔閱讀介面：米白底、暖陶色、英文襯線標題，移除首頁宣傳卡；播放頁提供影片與課程資訊。
- 原創「書頁＋播放」Icon，已套用 iOS、Android（含 adaptive / monochrome）與 macOS。

Advanced 使用官方 YouTube `/embed`，依實際安裝的 App ID 設定 Referer，保留官方播放器與控制項。全螢幕操作置於影片區域之外。

文章僅使用公開資訊及官方入口；會員全文與獨立廣播不在此版範圍。過去月份目錄若無法核對，顯示尚未確認，不將當月資料冒充歷史課程。目前目標平台為 Android／iOS；桌面和 Web 的影片頁提供官方外開入口。Flutter Web 直接抓取來源仍可能受 CORS 限制。

## 開發與執行

目前工具鏈：Flutter 3.41.2 / Dart 3.11。Android 最低 API 24；iOS 最低 15（本機 Xcode 27 的模擬器最低支援版本）。

為避開本機 Xcode 27 `lipo` 的多架構驗證問題，模擬器設定使用 Apple Silicon 的 `arm64`；Intel Mac 開發時需將 `ios/Flutter/Debug.xcconfig` 與 `Release.xcconfig` 的模擬器架構改為 `x86_64`。手機架構與既有簽章設定未更動。

```sh
flutter pub get
flutter devices
flutter run -d <裝置或模擬器ID>
```

## 檢查

```sh
dart format --output=none --set-exit-if-changed lib test tool integration_test test_driver
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator
```

自動單元與 widget 測試使用小型合成 fixtures，不連外。可另外手動執行真實來源檢查（內容隨日期及供應商狀態變動）：

```sh
dart run tool/check_sources.dart
flutter drive --driver test_driver/playback_driver.dart --target integration_test/playback_test.dart -d <模擬器ID>
```

整合測試使用真實官方頁面，驗證原生 WebView 載入與全螢幕前後文件保留；不等同逐集影音串流、音訊、DRM 或地區可用性保證。桌面截圖若平台支援會寫入 `build/verification/`。

可另加 `--dart-define=VERIFY_STREAMS=true` 嘗試靜音串流與播放進度檢查；此項需要供應商當時允許載入，並不在日常測試預設範圍。

## Icon 原始檔

`assets/branding/app-icon.svg` 是可編輯的向量原稿，`app-icon.png` 是 1024px 不透明版本。macOS 上可用內建 Swift / CoreGraphics 重新產生各平台尺寸：

```sh
swift tool/generate_icons.swift
```

## 主要程式

- `lib/domain/lesson.dart`：雜誌與每日課程模型。
- `lib/data/lesson_repository.dart`：三刊解析、日期核對與快取。
- `lib/features/library/library_page.dart`：雜誌、日期及課程首頁。
- `lib/features/media/player_page.dart`：官方播放器及全螢幕生命週期。
- `lib/preferences.dart`：偏好儲存。

來源調查與已知限制見 [docs/source-feasibility.md](docs/source-feasibility.md)。正式發佈前需另設正式 bundle/application ID 與 Android release 簽章；專案目前沿用 Flutter 的開發設定。
