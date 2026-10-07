# File search / 檔案搜尋

## English

In Cue, type **`f`**, a **space**, then part of a filename: **`f report`**, **`f .pdf`**, or **`f 發票`**. Uppercase **`F`** works too. This is an explicit file-search mode; typing only `f` still searches apps and commands. The blank `f ` prefix does not list recent files or start a broad search.

Results include files and folders. Each row shows its filename and parent folder so identical names are distinguishable. Use **Up/Down** and **Return**, click a result, or press **Command+1–9** to open it in its default macOS application; a folder opens in Finder. Cue shows at most nine results without scrollbars. Make the filename more specific to narrow a large set. Exact filenames come first, then names beginning with the text, then names containing it, ignoring case and accents. The search text is literal, not a wildcard expression.

The search uses macOS's existing **Spotlight index of local volumes**. Cue does not crawl your disk, read document contents, or create a separate index. It excludes hidden items, operating-system and library folders, and internal app-bundle resources. Indexed user documents in `~/Library/Mobile Documents` (iCloud Drive) and `~/Library/CloudStorage` remain eligible. Unindexed disks and Spotlight-excluded folders will not appear; access restrictions can also limit results, and new or renamed files may take time to reach Spotlight. Network volumes are outside this search. On Macs with a network-mounted home directory, this version leaves file search unavailable rather than querying that remote home. If an expected item is missing, check that Spotlight can find it and that the location is not excluded from Spotlight search. Cue does not request Full Disk Access automatically.

Only `f ` searches start index work, and editing or dismissing the launcher cancels the previous request. Searching shows a small progress indicator and does not block typing. While a new query is pending, already visible filenames that still match remain usable and the panel keeps its height; unrelated rows disappear immediately. Once you move the selection among retained rows, their order and numbered shortcuts stay fixed until the next edit. Results are a snapshot rather than a continuously monitored query. The search examines bounded sets of index candidates, so an extremely broad term may not surface every matching file. Queries longer than 1,024 UTF-8 bytes are not searched; refine them instead.

Searching works with **Cue network access off**. Neither file queries nor paths are added to Cue's search-learning history. **Command+K** and **Command+Return** do not turn a file query into a Google or GPT request; remove `f ` to return to ordinary text actions. Opening an iCloud placeholder or a file handled by a networked application is an explicit handoff to macOS or that app, which may download or synchronize the file independently of Cue's network switch.

### Verification

`./scripts/check-file-search.sh` runs an isolated native integration harness with a synthetic metadata provider, private preferences and a private pasteboard. It checks asynchronous results, cancellation and late responses, file-mode privacy, result limits, keyboard opening and native row labels without scanning user files, opening documents or activating Cue. CueCore tests cover parsing, ranking and candidate filtering. `./scripts/check-file-search-service.sh` checks literal Spotlight expressions, backend cancellation, the local-home scope policy, and a real metadata request restricted to its own empty temporary directory. These simulated checks do not establish completeness of a particular Mac's Spotlight index or actual default-app behavior; those require a coordinated manual check.

## 正體中文

在 Cue 輸入 **`f`**、一個**空格**，再輸入部分檔名，例如 **`f report`**、**`f .pdf`** 或 **`f 發票`**；大寫 **`F`** 也可以。這會進入檔案搜尋模式；只有 `f` 時仍搜尋 App 與指令。單獨的 `f ` 不會列出最近檔案，也不會開始大量搜尋。

結果包含檔案與資料夾，每列顯示檔名與所在資料夾，方便區別同名檔案。用**上下方向鍵**選取後按 **Return**、點選結果，或按 **Command+1–9**，即可使用 macOS 的預設 App 開啟；資料夾以 Finder 開啟。結果最多九列、不顯示捲軸，符合項目太多時可輸入更完整的檔名。排序依序為完全符合、檔名開頭符合、檔名包含文字，不區分大小寫與重音。搜尋文字照字面比對，不是萬用字元語法。

搜尋使用 macOS 既有的 **Spotlight 本機磁碟索引**。Cue 不會自行掃描硬碟、讀取文件內容或另建檔案索引；隱藏項目、系統與 Library 資料夾、App Bundle 內部資源不列入結果；但 `~/Library/Mobile Documents`（iCloud Drive）與 `~/Library/CloudStorage` 中已索引的使用者文件仍可搜尋。未建立索引的磁碟與 Spotlight 排除的位置不會出現；存取權限也可能限制結果，新增或更名後也可能要等 Spotlight 更新。搜尋範圍不含網路磁碟；若整個使用者個人檔案夾位於網路磁碟，這一版會停用檔案搜尋，以避免查詢遠端位置。找不到預期項目時，先確認 Spotlight 本身能否找到，以及該位置是否被排除。Cue 不會自動要求「完整磁碟存取權」。

只有 `f ` 搜尋才會啟動索引查詢，修改文字或關閉 Cue 視窗會取消前一個查詢。等待期間會顯示小型進度指示，打字仍保持可用。新的查詢完成前，仍符合文字的可見結果可以繼續操作，視窗維持原高度；不符合的舊結果立即移除。若已在保留的結果間移動選取，該次列表的順序與數字快速鍵會固定，直到下一次編輯。結果是本次搜尋的快照，不持續監看檔案。為保持輕量，索引候選項目有數量上限，過於寬泛的關鍵字可能不會涵蓋全部檔案。超過 1,024 UTF-8 位元組的查詢不會執行，請縮短文字。

**Cue 關閉網路時仍可搜尋**；搜尋字詞與檔案路徑不加入 Cue 的搜尋學習記錄。檔案模式中的 **Command+K**、**Command+Return** 不會把檔名交給 Google 或 GPT；刪除 `f ` 即可回到一般文字動作。開啟尚未下載的 iCloud 檔案，或交給本身會連網的 App，是你明確選擇後交由 macOS／該 App 處理，可能另行下載或同步，不受 Cue 的網路開關控制。

### 驗證方式

`./scripts/check-file-search.sh` 使用模擬索引服務、獨立偏好與私有剪貼簿，檢查非同步結果、取消與過期回覆、檔案模式隱私、九列上限、鍵盤開啟及原生結果文字。測試不搜尋使用者檔案、不開啟文件，也不搶走焦點。CueCore 測試涵蓋查詢解析、排序與候選項目過濾。`./scripts/check-file-search-service.sh` 另驗證 Spotlight 查詢語法、服務取消、本機個人檔案夾範圍政策，並對測試自行建立的空暫存資料夾執行一次真正的索引查詢。這些模擬不能證明個別 Mac 的 Spotlight 索引完整度或預設 App 的實際行為，仍需另行安排手動驗證。

## Local command history / 本機指令歷史

When Command History recording is on (the default), an explicit launcher action saves its input and action locally, including Google/GPT text, calculations and filename queries. Drafts and GPT responses are excluded. This is separate from search-learning data and is never attached to API requests. Use **history** to delete records, or its **History Settings** to stop recording or clear all. See [Command History](command-history.md).

指令歷史預設開啟：主啟動器明確執行的輸入與動作會存於本機，包含 Google／GPT 文字、計算式與檔名查詢；草稿與 GPT 回答不記錄。這與搜尋排序學習分開，也不會附加到 API 請求中。從 **history** 可刪除記錄，該頁的**指令歷史設定**可關閉記錄或清空，詳見[指令歷史](command-history.md)。
