# Command history / 指令歷史

## English

Open Cue with **Option+Space**, leave the input empty, and press **↑** to recall the last executed input. Continue ↑ for older entries and **↓** for newer ones. Down past the newest, or **Esc**, returns to blank. **Return** runs the recalled action. Editing ends recall; ordinary search and IME composition retain their usual arrow-key behavior.

Type **`history`**, **`command history`**, or **`指令歷史`** for a searchable history page. Each page has up to nine numbered rows; the page buttons or moving beyond the last row show more. **Use ↩** / **Command+1–9** restores the input and original action without executing it; press Return in the launcher when ready. Missing apps, files or browsers leave the selection empty, rather than substituting another action. Executing still checks the current network and feature permissions.

- **Delete** on an empty history search, or **Command+Delete**, deletes the selected entry. Otherwise plain Delete edits the search.
- The gear / **Command+,** opens feature settings: recording on/off and **Clear All History**, followed by confirmation. Recording is on by default; turning it off retains existing history until deletion or expiry.
- History includes explicitly submitted launcher actions: Google/GPT text, calculations, conversions, filename queries, apps and commands, including failed attempts. Drafts, action choosers, GPT answers, clipboard contents and other apps’ selected text are excluded. Opening Clipboard or Emoji is remembered as a command; searches/content inside those pages are not recorded here.

Repeated input for the same action moves to the top; using the same text with Google and GPT remains two entries. Limits: **200 entries, 30 days, 512 KiB of text**; inputs over **32 KiB** are skipped. Expired records are pruned on startup and when Cue/history next opens. JSON is saved only on this Mac, with owner-only permissions, at `~/Library/Application Support/com.yyhsiu.cue/CommandHistory/history.json`. History is separate from ranking, excluded from settings exports, and never sent to a service. The recording switch is local to each Mac.

Recall uses a memory snapshot. Loading and writes run in the background; launcher typing does not scan the history file.

## 正體中文

用 **Option+Space** 叫出 Cue，在空白輸入欄按 **↑** 回看最近執行的輸入，繼續 ↑ 看較舊記錄，**↓** 看較新記錄。往下超過最新一筆，或按 **Esc**，會回到空白。**Return** 執行回看的動作；修改文字就結束回看。一般搜尋仍用上下鍵選結果，中文組字也保留原本的上下鍵操作。

輸入 **`history`**、**`command history`** 或**「指令歷史」**開啟可搜尋的歷史頁，每頁最多九筆。使用翻頁按鈕，或在最後一列繼續往下，可看更多記錄。**使用 ↩**／**Command+1–9** 將輸入與原動作放回主視窗，不會立即執行；確認後再按 Return。原本的 App、檔案或瀏覽器無法找到時，不會自動改選其他動作。執行時也仍會檢查目前的網路與功能開關。

- 搜尋欄空白時按 **Delete**，或按 **Command+Delete**，可刪掉選取的記錄；有搜尋文字時，單按 Delete 會編輯文字。
- 齒輪／**Command+,** 開啟該功能設定，可關閉記錄，或**清空所有指令歷史**並確認。預設開啟記錄；關閉後既有記錄仍可使用，直到到期或自行刪除。
- 記錄包含主啟動器中明確送出的 Google／GPT 文字、計算式、換算、檔名查詢、App 與指令，也包含執行失敗的嘗試。草稿、動作選單、GPT 回答、剪貼簿內容與其他 App 選取的文字不記錄。開啟剪貼簿或 Emoji 頁會記成指令，但那些頁面內的搜尋與內容不會加入這份歷史。

相同輸入執行相同動作會移到最上方；分別用 Google 與 GPT 執行則保留兩筆。最多 **200 筆、30 天、512 KiB 文字**；超過 **32 KiB** 的輸入不記錄。到期記錄在啟動或下次開啟 Cue／歷史頁時清理。本機 JSON 位於 `~/Library/Application Support/com.yyhsiu.cue/CommandHistory/history.json`，預設只有你的帳號可讀取。它與搜尋排序學習分開，不隨設定匯出，也不會傳給任何服務；記錄開關只適用於目前這台 Mac。

上下鍵只讀取記憶體快照；載入與存檔都在背景，一般打字不會掃描歷史檔案。
