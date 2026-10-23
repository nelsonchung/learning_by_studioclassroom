# 三刊資料來源可行性驗證

觀察日期：2026-10-23，Asia/Taipei。驗證範圍：2026-10-20 至 2026-10-23，未登入的 HTTP GET、公開 HTML／頁面資料及桌面 Chrome 播放抽查。機器可讀證據見 [來源紀錄](evidence/source-probe-2026-10-23.json)。

後續已完成影片版實作及 iOS 模擬器的頁面／全螢幕檢查，見 [實作與驗證紀錄](verification/implementation.md)。本文件以下的「尚未建立播放器」等描述保留來源調查當時的驗證狀態。

## 結論與第一版範圍

依使用者實測與本次調查，第一版以影片為核心：三刊切換 → 四日課程索引 → 選擇日期 → 播放當日可用節目。每日節目不需要空英帳號登入；獨立 Radio 網頁的登入限制不適用於每日影片入口。

三刊目前找到的免費每日影片皆涵蓋 10/23、10/22、10/21；10/20 不在本次來源列出的免費集數中。四日索引仍可顯示主題，10/20 的播放狀態應為「目前免費清單未列出」，不能標記成「當天無節目」，也不能拿目前第 1 集代替。

文章以中英文標題、分類、公開簡介及官方入口為第一版範圍。公開試讀可讀，但三刊四日完整文章不能由目前資料來源保證。獨立廣播入口要求會員登入；第一版不實作帳號登入、會員廣播串流或從影片抽取音訊。

影片播放、文章完整度、廣播存取三者分別標記，不用單一「需要登入」遮蔽整個課程。

## 已確認的官方來源

| 用途 | 來源與解析重點 |
| --- | --- |
| LT 月目錄 | [lt.studioclassroom.com](https://lt.studioclassroom.com/)，`.lessonBOX` 內的 `.lessonDATE`、`.lessonTITLE_e`、`.lessonTITLE_c`；文章 URL 取真實 anchor |
| SC 月目錄 | [sc.studioclassroom.com](https://sc.studioclassroom.com/)，各主題的日期、中英文標題、分類、`sc_article.php` anchor；舊式表格結構需獨立解析 |
| AD 月目錄 | [ad.studioclassroom.com](https://ad.studioclassroom.com/)，`.index_article` 內 `.index_article_date`、`.a_eng_title`、`.a_cht_title`；多數非試讀文章 anchor 在 HTML 註解內，不能當成可用入口 |
| LT 每日節目入口 | [每日節目](https://m.studioclassroom.com/tv-programs.php?level=lt)，本次 iframe 為 `https://www.linetv.tw/player/10130/eps/1` |
| SC 每日節目入口 | [每日節目](https://m.studioclassroom.com/tv-programs.php?level=sc)，本次 iframe 為 `https://www.linetv.tw/player/10131/eps/1` |
| LT／SC 日期清單 | LINE TV 公開頁面 `window.__INITIAL_STATE__` → `entities.dramaInfo.byId[dramaId].eps_info`，取得集號、含月日標題及 `svod`；這是頁面內資料，不是已承諾穩定的官方 API |
| AD 每日節目入口 | AD 首頁 iframe 指向 [三日免費播放清單](https://www.youtube.com/playlist?list=PL8UOfOD7HDmIvReJUbOQoPkf6pUBBOP3n)；本次公開頁 `ytInitialData` 的 `lockupViewModel` 包含影片 ID 與日期標題。YouTube 結構可能更動，需保留官方清單入口備援 |

LINE TV 本次 `svod=false` 且未帶 Cookie 的 GET 可取得節目清單，支持免費資源判定。Chrome 播放抽查未要求輸入帳密；瀏覽器是既有使用者環境，未登出現有第三方帳號，不把該播放抽查宣稱為全新無登入環境測試。使用者另已確認每日節目不需帳密。

## 三刊 × 四日矩陣

「列出」表示官方供應商公開頁提供指定日期的影片項目，不等於每集均已在雙平台 App 內實測播放。廣播欄均指獨立 Radio 網頁；無法登入後核對各日是否實際有音檔。

| 雜誌 | 日期 | 文章主題 | 公開文章狀態 | 每日影片 | 獨立廣播 |
| --- | --- | --- | --- | --- | --- |
| LT | 10/23 | 許師傅手工麵線 | 公開試讀，含正文與單字 | 列出，[LINE TV 第 1 集](https://www.linetv.tw/player/10130/eps/1)；桌面播放進度有前進 | 入口要求登入，各日未驗證 |
| LT | 10/22 | 拍照小撇步 | 文章頁只有標題、日期、作者，未提供正文 | 列出，[第 2 集](https://www.linetv.tw/player/10130/eps/2)，標題標示 1022、下集 | 同上 |
| LT | 10/21 | 拍照小撇步 | 同上，主題涵蓋 10/21、10/22 | 列出，[第 3 集](https://www.linetv.tw/player/10130/eps/3)，標題標示 1021、上集 | 同上 |
| LT | 10/20 | 你喜歡怎麼吃馬鈴薯？ | 文章頁只有標題、日期、作者，未提供正文 | 本次免費清單未列出 1020 | 同上 |
| SC | 10/23 | 阿根廷：對比之境 | 文章頁有中英文簡介，全文導向官方訂閱 | 列出，[LINE TV 第 1 集](https://www.linetv.tw/player/10131/eps/1)；桌面播放進度有前進 | 入口要求登入，各日未驗證 |
| SC | 10/22 | 阿根廷：對比之境 | 同上，主題涵蓋 10/22、10/23 | 列出，[第 2 集](https://www.linetv.tw/player/10131/eps/2)，標題標示 1022、上集 | 同上 |
| SC | 10/21 | 留校察看驚魂 | 文章頁有中英文簡介，全文導向官方訂閱 | 列出，[第 3 集](https://www.linetv.tw/player/10131/eps/3)，標題標示 1021、下集 | 同上 |
| SC | 10/20 | 留校察看驚魂 | 同上，主題涵蓋 10/20、10/21 | 本次免費清單未列出 1020 | 同上 |
| AD | 10/23 | 夜之樂章 | 月目錄有標題與簡介，無可見正常文章連結 | 列出，[YouTube](https://www.youtube.com/watch?v=x0aobOliJG4)；桌面嵌入播放出現進行中的字幕 | 入口要求登入，各日未驗證 |
| AD | 10/22 | 我們需要奪回我們的大腦！ | 同上，主題涵蓋 10/21、10/22 | 列出，[YouTube](https://www.youtube.com/watch?v=icArZIi1RVc)，標題標示 10/22 | 同上 |
| AD | 10/21 | 我們需要奪回我們的大腦！ | 同上 | 列出，[YouTube](https://www.youtube.com/watch?v=VURLMGfbHTQ)，標題標示 10/21 | 同上 |
| AD | 10/20 | 食物與恐懼的囚籠 | 月目錄有標題與簡介，無可見正常文章連結 | 本次免費清單未列出 10/20 | 同上 |

上表 LINE TV 第 2、3 集網址依同一供應商清單的 `number` 組成，日期對應來自 `eps_info.title`；逐集播放器未全部抽查。不能保存成永久的日期連結：目前第 1 集代表今天，未來可能被新節目替換。每次重新開啟前須重新讀取清單並核對日期與標題；同日跨年也不能僅以 MMDD 比對。

### 文章證據入口

- LT：[10/19–20](https://lt.studioclassroom.com/lt_articles.php?volume=2026-10-01&article_id=10l08)、[10/21–22](https://lt.studioclassroom.com/lt_articles.php?volume=2026-10-01&article_id=10l09)、[10/23 試讀](https://lt.studioclassroom.com/lt_articles.php?volume=2026-10-01&article_id=10l10)。實際 GET 前兩頁未見正文，不能只看 HTTP 200 就判斷全文可用。
- SC：[10/20–21](https://sc.studioclassroom.com/sc_article.php?article_id=10b09&volume=2026-10-01&zoot=09)、[10/22–23](https://sc.studioclassroom.com/sc_article.php?article_id=10b10&volume=2026-10-01&zoot=10)。頁面明確提示完整版在官方電子雜誌。
- AD：本次四日主題只採[月目錄](https://ad.studioclassroom.com/)公開內容；不從註解中的停用連結推定可以取得正文。

### 獨立廣播證據入口

- [LT Radio](https://m.studioclassroom.com/radio.php?level=lt) → `login_radio.php?req=1&radio=lt`。
- [SC Radio](https://m.studioclassroom.com/radio.php?level=sc) → `login_radio.php?req=1&radio=sc`。
- [AD Radio](https://m.studioclassroom.com/radio.php?level=ad) → `login_radio.php?req=1&radio=ad`；原始連結來自 [AD Site Map](https://ad.studioclassroom.com/ad_sitemap.php)。

以上皆為未帶 Cookie 的 GET；只有導向登入頁的證據，不能據此判定登入後是否還需訂閱。

## 日期與跨月驗證

1. **多日主題已驗證**：LT 10/21–22、SC 10/22–23、AD 10/21–22。每日節目的影片 ID／集號不同，Article 與 DailyLesson 必須分開。
2. **頁面時間不能當影片日期**：SC 每日節目頁兩次 GET 的 `<time>` 分別為 `2026/10/23 10:43:33` 與 `2026/10/23 10:46:43`，iframe 來源相同。因此該時間不構成影片日期的獨立證據。
3. **AD 手機頁資訊不一致**：本次 `tv-programs.php?level=ad` 的 iframe 影片 ID 為 `x0aobOliJG4`，但文字主題仍是較早的食物主題；首頁及 YouTube 影片標題對應 10/23。不能只用手機頁標題配對。
4. **跨月查詢尚未找到可靠方式**：對各刊 `default.php?volume=2026-09-01` 進行一次明示探索，三者均 HTTP 200，但仍回十月目錄及 `volume=2026-10-01` 的文章連結。此參數被忽略，不能宣稱支援歷史月份。
5. **跨月缺口處理**：第一版若月底／月初日期無法由即時目錄或已快取索引確認，顯示「此日期課程資料尚未確認」及官方入口；不得寫成無課程。要完整支援跨月，後續需找到官方歷史索引或持續保存經確認的主題中繼資料；安裝當下沒有歷史快取時仍有缺口。

## 播放實測與剩餘缺口

| 項目 | 本次結果 |
| --- | --- |
| SC 當日 LINE TV | 桌面 Chrome 播放進度由 0 前進至 0:12，播放器總長 25:05，未要求輸入帳密 |
| LT 當日 LINE TV | 桌面 Chrome 播放進度前進至 0:26，播放器總長 24:01，未要求輸入帳密 |
| AD 當日 YouTube 嵌入 | 從官方首頁按播放後出現進行中的節目字幕，未要求輸入帳密 |
| 其他六個已列出日期影片 | 供應商清單資料可取得；未逐集實播 |
| Android App 內 WebView | 尚未建立播放器；本機 `adb` 不在 PATH，沒有已確認可用的 Android 測試裝置 |
| iOS App 內 WebView | 尚未建立播放器；目前無已開機模擬器。未對偵測到的個人無線裝置安裝 App |
| 全新無登入瀏覽器環境 | 來源 GET 未帶 Cookie，清單可取得；Chrome 為既有使用者 session，未以登出方式改變使用者環境 |

桌面播放成功不等於 iOS／Android 內嵌成功。App 實作階段仍須驗證 WebView 媒體設定、返回／離開停止播放、官方頁外開備援與來源失效提示。

## 實作交接

- 先完成影片版核心，不把會員登入當作首頁或每日影片的前置條件。
- 首頁維持四個日曆日；影片可用性以即時清單為準，未列出與解析失敗使用不同狀態。
- LT／SC 由每日節目頁發現供應商 URL，再解析對應清單；不要把本次的 drama ID、集號與日期當永久常數。
- AD 由首頁發現播放清單，再以影片標題月日加目錄年份／主題核對；資料結構改版時保留官方清單入口，不猜影片 ID。
- 影片播放頁用官方播放器，保留供應商控制項。文章提供公開資料與官方來源，獨立廣播呈現存取限制；不加入帳號、抓取會員內容或音訊抽取流程。
- 索引 JSON 與來源差異用 fixtures 做後續解析測試；本次紀錄只保存中繼資料及結果，未保存全文、影音或 Cookie。

本次完成公開來源調查與桌面抽查。四日完整免費影片、歷史月索引與雙平台 App 內播放仍有上述明確缺口；不能將階段 A 報告誤讀為全部產品驗收通過。
