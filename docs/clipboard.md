# Clipboard History / 剪貼簿記錄

## English

Clipboard History is included in [Cue 0.3.0](https://github.com/hsiuhsiu/cue/releases/tag/v0.3.0).

### Use history

Open Cue, which starts with just an empty input field, without initial results, a placeholder, a footer, or shortcut hints. **Command+,** still opens Cue's main Settings from there. Type `clipboard` or `剪貼簿`, select **Clipboard History**, and press Enter. Recording starts **off**. Choose **Enable Clipboard History** to record new copies of text and links. Enabling or resuming recording does not import the contents already on the system clipboard.

Saved clipboard history remains visible with an empty search field. Each record displays its number and the date and time it was copied. The compact window adapts to the result count and shows the nine most recent matching records, with no scrollbars. Search covers all saved history; records beyond the nine displayed are retained and can be found by refining the query. The display limit does not change the storage or retention limits below. A subtle blue tint reflects Cue's icon in both light and dark appearances.

**Command+1–9 immediately copies the corresponding result and closes Cue**, without another Return press. In the main launcher, the same shortcuts immediately open the numbered app or run the numbered command. Both result lists are limited to nine visible matches.

| Action | Control |
| --- | --- |
| Search saved text and links | Type in the history search field |
| Select an item | Up/Down or a single click |
| Copy the selected item and close Cue | Return, **Copy**, or double-click |
| Copy a numbered result and close Cue immediately | Command+1–9 |
| Paste into another app | Command+V in that app |
| Delete the selected history item with an empty search field | Delete/Backspace |
| Delete the selected history item, including filtered results | **Delete** button or Command+Backspace |
| Open or close clipboard settings | The page's gear or Command+, |
| Go back | Esc: settings → history → launcher |

When the search field contains text, Delete/Backspace edits the query normally. Use the **Delete** button or Command+Backspace to remove the selected result without changing the query.

Copying does not paste automatically and does not require Accessibility permission. Deleting a history item removes that saved record; it does **not** clear the current system clipboard.

### Recording and retention

Clipboard settings belong to this feature page. Choose a retention period of **1 hour**, **1 day**, **7 days** (default), **30 days**, or **No time limit**. Exact duplicate text moves to the top with a new copied time instead of creating another record.

History holds at most **500 items or 4 MiB of text**, whichever limit is reached first. Each item can contain at most **256 KiB of UTF-8 text**; larger copies are skipped. Oldest items are removed when history is full, including with **No time limit**.

Turning recording off stops new captures, while saved history remains searchable and can still be copied or deleted. Expiration continues while recording is off: Cue removes expired records while it runs or when history next loads. Pausing does not extend an item's retention period.

### What is stored

Cue records **text and links only**, not images or files. Links are stored as text; Cue does not fetch their contents. It skips copies carrying known concealed, transient, or automatically generated clipboard markers. Those markers depend on the source app, so this cannot identify every sensitive copy.

History stays in `~/Library/Application Support/com.yyhsiu.cue/Clipboard/history.json`, with file and directory permissions restricted to your macOS account. The file contains readable text; Cue does not add separate encryption. This feature does not upload history or sync it to a cloud service.

## 正體中文

剪貼簿記錄已包含在 [Cue 0.3.0](https://github.com/hsiuhsiu/cue/releases/tag/v0.3.0)。

### 使用記錄

叫出 Cue 時，只會顯示空白輸入欄，不會先列出結果，也沒有提示文字、底列或快速鍵提示。此時仍可按 **Command+,** 開啟 Cue 的主要設定。輸入 `clipboard` 或「剪貼簿」，選擇**剪貼簿記錄**並按 Enter。記錄功能**預設關閉**；選擇**啟用剪貼簿記錄**後，才會開始記錄新拷貝的文字與連結。啟用或恢復記錄時，不會匯入系統剪貼簿原本已有的內容。

剪貼簿頁的搜尋欄空白時，仍會顯示已儲存的記錄。每筆記錄都會顯示編號，以及拷貝的日期與時間。視窗會依結果數量調整高度，最多顯示符合搜尋條件的最近九筆記錄，不顯示捲軸。搜尋範圍仍涵蓋全部已儲存記錄；超過九筆的記錄會保留，可輸入更精確的文字尋找。顯示上限不影響下方說明的儲存容量與保留時間。淺色與深色外觀都採用呼應 Cue 圖示的淡藍色調。

按 **Command+1–9 會立即拷貝對應編號的結果並關閉 Cue**，不必再按 Return。在主啟動器中，相同快速鍵會立即開啟對應的 App 或執行指令。兩種結果清單都最多顯示九筆符合項目。

| 操作 | 方式 |
| --- | --- |
| 搜尋已儲存的文字與連結 | 在記錄頁的搜尋欄輸入文字 |
| 選取項目 | 上／下方向鍵或點一下 |
| 拷貝所選項目並關閉 Cue | Return、**拷貝**按鈕，或點兩下 |
| 立即拷貝指定編號的結果並關閉 Cue | Command+1–9 |
| 貼到其他 App | 在該 App 按 Command+V |
| 搜尋欄空白時刪除所選記錄 | Delete／Backspace |
| 刪除所選記錄，包含篩選後的結果 | **刪除**按鈕或 Command+Backspace |
| 開啟或關閉剪貼簿設定 | 記錄頁的齒輪或 Command+, |
| 返回 | Esc：設定 → 記錄 → 啟動器 |

搜尋欄有文字時，Delete／Backspace 會照常編輯搜尋文字。若要保留搜尋文字並刪除所選結果，請使用**刪除**按鈕或 Command+Backspace。

拷貝後不會自動貼上，也不需要「輔助使用」權限。刪除記錄只會移除已儲存的項目，**不會**清空系統剪貼簿目前的內容。

### 記錄與保留時間

剪貼簿設定位於自己的功能頁。保留時間可選擇 **1 小時**、**1 天**、**7 天**（預設）、**30 天**或**不依時間清除**。再次拷貝完全相同的文字時，原有項目會移到最上方並更新拷貝時間，不會增加重複記錄。

最多保留 **500 筆或 4 MiB 文字**，以先達到的限制為準。單筆最多 **256 KiB 的 UTF-8 文字**，超過的內容不會儲存。記錄滿時會移除最舊的項目；選擇**不依時間清除**時也適用。

關閉記錄後會停止擷取新內容，既有記錄仍可搜尋、拷貝或刪除。關閉記錄期間仍會計算保留期限；Cue 執行時或下次載入記錄時，會移除已到期項目。暫停不會延長項目的保留時間。

### 儲存的內容

Cue 只記錄**文字與連結**，不記錄圖片或檔案。連結以文字儲存，不會自動抓取網頁內容。若來源帶有已知的隱藏、暫存或自動產生剪貼簿標記，Cue 會略過；這些標記由來源 App 提供，因此無法辨識所有敏感內容。

記錄儲存在 `~/Library/Application Support/com.yyhsiu.cue/Clipboard/history.json`，檔案與資料夾權限限制為目前的 macOS 帳號。檔案包含可讀文字，Cue 不會另行加密。此功能不會上傳記錄，也不會同步到雲端服務。
