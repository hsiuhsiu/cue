# Chinese conversion / 簡繁互轉

## English

1. Select text in another app's editable text field.
2. Invoke Cue with your usual shortcut (Option+Space by default).
3. Type `st` to convert Simplified Chinese to Traditional Chinese with Taiwan
   vocabulary, or `ts` for the reverse direction with mainland China vocabulary.
4. Press Return or the displayed Command+number. Cue replaces only the selection
   and returns focus to the original app. Its normal Command+Z undoes the paste.

On first use, allow **Cue** in **System Settings → Privacy & Security →
Accessibility**. Cue's conversion settings link opens that page. Select the text
again afterward; no old selection is saved for later execution.
On macOS 27, the linked permission page is labeled **Device Control and Data Access**.

Search for `chinese settings`, `conversion settings`, or `簡繁設定` to edit the two
search aliases. Command-comma also opens this page when a conversion command is
selected. Save applies immediately and persists across restarts. Exact aliases
take priority over other matches; they do not trigger conversion until you execute
the result. Aliases ignore case, accent, and character width; use different short
names for each direction (up to 32 UTF-8 bytes). An empty value disables that
alias; the full command names remain searchable.

Cue remembers the source app before activating its own search field. Esc returns
to that app; switching away deliberately never pulls focus back. Conversion
returns to the original app and observes its focused field before pasting, with
no unconditional delay and no repeated activation request.

Conversion is fully offline, using bundled OpenCC dictionaries for character forms
and regional vocabulary. First use does not download anything, and turning off
network access keeps the same dictionaries and conversion rules. Text is never
sent to a server or saved by the conversion feature. Dictionaries load from the
app bundle on first execution in the background, not while typing.
The search-learning feature records the successful command/query, not selected text.

Cue temporarily uses the clipboard to perform the source app's normal Paste and
restores its original representations afterward, provided another copy operation
has not replaced them. Cue's Clipboard History skips this temporary data and the
restoration. Another clipboard manager may still observe clipboard changes.

Supported fields must expose an editable selection and their text through macOS
Accessibility. Password fields, read-only pages, unsupported editors, selections
over 256 KiB, and documents over about one million UTF-16 units are rejected.
Cue rechecks the original app, field, selection, and document before pasting. A
changed selection aborts the operation. It never overwrites the entire field as
a fallback or retries an unconfirmed paste. If a message says the replacement
could not be confirmed, inspect the original app before retrying. In that case
Cue leaves converted text on the clipboard instead of restoring older contents:
a delayed Paste must not insert the old clipboard into the selection.

This is phrase/dictionary conversion, not contextual rewriting or translation.
Ambiguous words follow OpenCC's dictionary choices and conversion is not always
reversible. Plain text is pasted; rich formatting within the replaced selection
may change according to the source app's paste behavior.

See [dictionary provenance, tests, and performance](chinese-conversion-data.md).

### Permission still unavailable after rebuilding or updating

Cue's current builds use ad-hoc signing. Rebuilding or installing a different
build can change its code identity, leaving macOS with permission for the previous
copy. The switch can appear enabled while the running Cue still has no access;
turning the old entry off and on may not refresh that saved identity.

1. Quit Cue from its menu bar menu.
2. Open **System Settings → Privacy & Security → Accessibility** (called
   **Device Control and Data Access** on macOS 27).
3. Select the old **Cue** entry and remove it with the minus button. Add the
   currently installed app with the plus button, then enable it. The source-build
   installer uses **`~/Applications/Cue.app`** by default; use your actual install
   location if different. In the file picker, Command+Shift+G lets you enter it.
4. Relaunch that same installed copy and reopen **Chinese Conversion Settings**
   to refresh the permission status. Reselect text in the original app and retry.

Grant access to the copy you actually launch. A copy in `.build`, Xcode's build
folder, or an old install location may have a different identity. This repair
only changes Cue's entry; other apps' permissions do not need to be reset.

## 正體中文

1. 在其他 App 的可編輯欄位選取文字。
2. 用平常的快速鍵叫出 Cue，預設為 Option+Space。
3. 輸入 `st` 轉為正體中文與台灣用詞；輸入 `ts` 轉為簡體中文與中國大陸用詞。
4. 按 Return 或顯示的 Command+數字，即會取代選取範圍並回到原 App；可用原
   App 的 Command+Z 復原。

首次使用需在「系統設定 → 隱私權與安全性 → 輔助使用」允許 **Cue**，功能設定
內的按鈕可開啟該頁面。授權後請重新選取文字再執行，不會儲存先前的選取範圍。
macOS 27 英文介面中，這個權限頁面名稱為 **Device Control and Data Access**。

搜尋 `簡繁設定`、`chinese settings` 或 `conversion settings` 可自訂兩個別名；
選到轉換指令時按 Command+逗號也會開啟此頁。儲存後立即生效，重新開啟 Cue
仍會保留。完整輸入別名會優先找到指定指令，仍需執行結果才會轉換。別名不區分
大小寫、重音與全半形；兩個方向須使用不同名稱，最多 32 個 UTF-8 位元組。留空
可停用該別名，完整指令名稱仍可搜尋。

Cue 會先記住來源 App，再取得搜尋欄的鍵盤焦點。按 Esc 會回到來源 App；主動
切換其他視窗不會被拉回。轉換時只要求返回原 App 一次，確認原欄位實際取得
焦點後才貼上，不加入固定等待時間。

使用內附的 OpenCC 詞庫在本機離線處理字形與地區用詞，不會將文字傳到伺服器，
轉換功能也不會儲存選取內容。首次使用不需下載，關閉網路後仍使用相同詞庫與規則。
詞庫只在第一次執行時由背景從 App 內載入，打字搜尋不需等待。
搜尋學習只會記錄成功執行的指令與搜尋字詞，不含選取文字。

為了保留原 App 的原生貼上與復原行為，Cue 會暫時使用剪貼簿，完成後還原原先
格式與內容。若期間有其他拷貝動作，則保留較新的內容。Cue 的剪貼簿記錄會略過
這次暫存及還原，但其他剪貼簿管理程式仍可能觀察到變化。

欄位必須透過 macOS 輔助使用提供可編輯的選取範圍與文字。密碼欄位、唯讀頁面、
不支援的編輯器、超過 256 KiB 的選取文字，以及超過約一百萬個 UTF-16 單位的
文件不適用。貼上前會再次檢查來源 App、欄位、選取範圍及文件內容；若已變動就
取消，不會改以覆寫整個欄位處理，也不會在結果不明時自動重貼。若顯示無法確認
取代結果，請先檢查原 App 再重試。此時轉換文字會留在剪貼簿，不還原舊內容，
避免延遲處理的貼上動作誤貼先前的剪貼簿內容。

這是字詞轉換，不是依上下文改寫或翻譯；多義詞採用 OpenCC 詞庫預設，來回轉換
不保證還原。貼入的是純文字，選取範圍內的富文字格式可能依原 App 的貼上行為改變。

詞庫來源、測試與效能見[資料說明](chinese-conversion-data.md)。

### 重新建置或更新後，仍顯示未取得權限

Cue 目前使用 ad-hoc 簽章。重新建置或安裝不同版本時，程式識別可能改變，macOS
卻仍保留給舊版本的授權。因此，即使開關顯示已開啟，正在執行的 Cue 仍可能沒有
權限；只將舊項目關閉再開啟，也不一定會更新已儲存的識別。

1. 從選單列選單結束 Cue。
2. 開啟「**系統設定 → 隱私權與安全性 → 輔助使用**」。macOS 27 英文介面中的
   頁面名稱為 **Device Control and Data Access**。
3. 選取舊的 **Cue** 項目，按減號移除，再按加號加入目前已安裝的 App 並允許。
   原始碼安裝腳本預設位置為 **`~/Applications/Cue.app`**；若自行指定其他位置，
   請使用實際安裝路徑。檔案選擇視窗內可按 Command+Shift+G 輸入路徑。
4. 重新開啟同一份已安裝的 Cue，再開啟「**簡繁轉換設定**」更新權限狀態。
   回到原 App 重新選取文字後再試。

請授權平常實際開啟的那一份 App。`.build`、Xcode 建置資料夾或舊安裝位置中的
另一份 Cue，可能有不同的識別。只需處理 Cue 的項目，不需要重設其他 App 的權限。

## Verification / 驗證

`scripts/check-selected-text.sh` uses synthetic accessibility state and private
pasteboards to exercise both conversion directions, cancellation, clipboard
restoration and replacement safety. `scripts/check-conversion-lifecycle.sh`
checks feature settings, session cancellation and responsiveness during large
conversions. Core tests validate dictionary conversion independently.

Real global-hotkey focus, per-editor replacement/undo behavior and macOS
permission prompts require coordinated desktop testing of the installed build.
Injected checks do not establish compatibility with every editor or prove that
a rebuilt executable has retained Accessibility permission.

上述檢查以合成輔助使用狀態、獨立剪貼簿及隔離設定驗證轉換、取消、剪貼簿還原、
設定返回與大量文字處理。實際全域快速鍵、各編輯器的取代／還原操作與 macOS
授權提示，仍需協調時間測試當前安裝版本；模擬檢查不能代表所有編輯器皆相容，
也不能證明重新建置後仍保有輔助使用授權。
