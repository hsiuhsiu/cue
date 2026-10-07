<p align="center">
  <img src="docs/branding/cue-icon.png" alt="Cue app icon" width="144" height="144">
</p>

<h1 align="center">Cue</h1>

<p align="center">Fast, simple, lightweight.</p>

<p align="center"><a href="https://yihsiu.org/cue/">Website / 官網</a></p>

Cue is a small native macOS launcher with quick GPT answers and translation, an instant calculator, unit and currency conversion, filename search, emoji search, Google search, link cleaning, searchable clipboard history, offline Chinese conversion, and system commands. It runs in the menu bar, opens with **Option+Space**, and searches installed applications using an in-memory index.

<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/branding/menu-bar-dark.png">
    <img src="docs/branding/menu-bar-light.png" alt="Cue menu bar icon" width="20" height="20">
  </picture>
  Look for Cue in the macOS menu bar. A small dot on its icon means an update is available.
</p>

## Download and install

[Download Cue 1.1.1 for Mac](https://github.com/hsiuhsiu/cue/releases/download/v1.1.1/Cue-1.1.1-universal.dmg) · [Release notes and checksums](https://github.com/hsiuhsiu/cue/releases/tag/v1.1.1) · [正體中文安裝說明](docs/installation.md)

The repository and release downloads are public.

Open the DMG, drag **Cue.app** into **Applications**, then open Cue from Applications. Cue appears in the menu bar and has no Dock icon. If replacing an existing copy, first choose **Quit Cue** from its menu; replacing the app preserves your settings.

The universal app contains Apple silicon (`arm64`) and Intel (`x86_64`) builds targeting **macOS 14 or later**. Automated execution checks ran on **macOS 27.0 on Apple silicon**, using Xcode 27; Intel and other macOS versions remain unverified. This release did not complete final installed-app desktop checks, a positive real-Spotlight fixture, or a full public updater installation. See the [release validation limits](https://github.com/hsiuhsiu/cue/releases/tag/v1.1.1).

The app has an **ad-hoc signature**, without Developer ID signing or Apple notarization. macOS may block its first launch. If you trust this release, follow the [first-launch instructions](docs/installation.md#首次開啟) using System Settings. Building from source is optional; downloading and installing the app does not require Xcode or Terminal.

## Features

The interface supports **English and Traditional Chinese (正體中文)**, including all settings, menus, search prompts, and Cue's status/error messages. It follows macOS by default. Choose **Settings → General & Interaction → App language** to use **Follow System**, **English**, or **正體中文**, then reopen Cue to apply the change. Cue keeps its name, and installed application names continue to follow macOS. Translations are cached outside the typing path.

The blue app icon appears in Finder and **About Cue**. The matching menu bar icon supports light and dark appearances and shows a small dot when an update is available. **Command+,** brings Settings to the front with keyboard focus, including when Settings was already open or minimized.

Cue discovers applications under `/Applications`, `/System/Applications`, `~/Applications`, and `/System/Library/CoreServices/Applications`, including nested folders. It also indexes Finder directly from `/System/Library/CoreServices/Finder.app`. Results show application names and icons. Ranking prefers exact, prefix, word-prefix, substring, then subsequence matches. The global shortcut uses the system hot-key API and does not require Accessibility permission.

Localized folders such as `~/Applications/Chrome Apps.localized` and visible links to application folders are included. Cue skips hidden folders and bundle contents, prevents link loops, and deduplicates apps. `~` means the current user's home folder. After installing or moving an app, run **Update App Index** to refresh the index in the background.

也包含 `~/Applications/Chrome Apps.localized` 這類本地化資料夾，以及指向 App 資料夾的可見連結；會跳過隱藏資料夾與套件內部、避免連結循環，並去除重複 App。`~` 是目前使用者的家目錄。安裝或移動 App 後，可執行**更新索引**，在背景重新掃描。

### App names and search aliases / App 名稱與搜尋別名

Cue searches an app’s display name, local bundle names, and `.app` filename while showing one result. For example, **Code** can also be found with **`visual`**, **`vs`**, or **`vsc`** through its `Visual Studio Code.app` filename. **Finder** is included in the app index.

For a personal shortcut, select an app and press **Command+E**, click its **…** button, or right-click it and choose **Edit Search Alias…**. Save one alias such as `vs` or `term`; entering it exactly puts that app before ordinary app and command matches. Clear the field and save to remove it. Aliases start with a letter and allow up to 32 letters, numbers, `-`, or `_`, without spaces. Duplicate app aliases and conflicts with Chinese conversion aliases are rejected. Aliases stay on this Mac, survive reindexing, and follow an app moved to another indexed folder when it has the same bundle identifier. Name preparation happens during background indexing; typing does not read app files or settings.

Cue 同時搜尋 App 的顯示名稱、本機 Bundle 名稱及 `.app` 檔名，同一個 App 只顯示一次。例如 **Code** 的檔名是 `Visual Studio Code.app`，因此也能用 **`visual`**、**`vs`** 或 **`vsc`** 找到。**Finder** 也會加入 App 索引。

要設定個人習慣的縮寫，選取 App 後按 **Command+E**、點該列的 **…**，或按右鍵選擇**編輯搜尋別名…**。每個 App 可儲存一個別名，例如 `vs` 或 `term`；完整輸入時，會優先於一般 App 與指令符合結果。清空欄位後儲存即可移除。別名以字母開頭，最多 32 個字母、數字、`-` 或 `_`，不含空白；不能與其他 App 或簡繁轉換別名重複。別名只存本機，更新索引後仍保留；App 移至另一個索引資料夾時，只要 Bundle 識別碼相同就會沿用。名稱整理在背景建立索引時完成，打字時不讀取 App 檔案或設定。

### File search / 檔案搜尋

Type **`f` + space + part of a filename**, such as **`f report`** or **`f 發票`**. Cue searches the local Spotlight index for files and folders, showing filenames and their parent paths. Use **Up/Down + Return**, click a result, or **Command+1–9** to open it with its default macOS app. Uppercase `F` also works; an empty `f ` shows no files. Results stay within nine rows. Search is fully local, does not scan document contents, and never falls back to Google or GPT in this mode. Spotlight exclusions and indexing delays apply. See the [file search guide](docs/file-search.md) for scope and privacy.

輸入 **`f`＋空格＋部分檔名**，例如 **`f report`** 或 **`f 發票`**，即可搜尋本機 Spotlight 索引中的檔案與資料夾；每列顯示檔名及所在路徑。用**上下方向鍵＋Return**、點選結果，或 **Command+1–9**，以 macOS 預設 App 開啟。大寫 `F` 也可；只有 `f ` 時不列出檔案，結果最多九列。搜尋完全在本機執行、不讀取文件內容，檔案模式不會轉成 Google／GPT 搜尋。結果受 Spotlight 排除位置及索引更新時間影響；範圍與隱私詳見[檔案搜尋說明](docs/file-search.md)。

### Personalized search

Cue learns from applications and commands you successfully open through the launcher. Within the same app matching category, it prefers the item you usually choose for that query, followed by usage frequency weighted toward recent use; exact app matches stay ahead of weaker app matches. A successful choice for the same query can also promote an app above a matching built-in command—for example, choosing iTerm2 for `it` can move it ahead of the incidental Traditional Chinese conversion match on the next invocation. Overall popularity alone does not change the order between apps and commands, and explicitly configured exact command aliases still come first. Merely typing, moving the selection, canceling, or a failed launch does not teach it anything. Clipboard contents, searches inside Clipboard History, Google queries, and GPT questions, translations and replies are excluded.

Learning stays on this Mac. Only successful queries, selected result identifiers, scores, and timestamps are saved in a small local file. Search uses a prepared in-memory snapshot; loading, score calculation, and saving happen in the background. An arriving update never moves the current rows while you are choosing a result. See [adaptive search behavior and performance](docs/performance.md).

Cue 會記住你在啟動器中成功開啟的 App 與指令。同一 App 符合程度內，優先考慮「這個關鍵字通常選哪個項目」，再參考使用頻率與近期使用情況；完全符合的 App 仍排在較弱的 App 符合結果前面。相同關鍵字的成功選擇也能讓 App 超過內建指令，例如用 `it` 成功開啟 iTerm2 後，下次叫出時就能超過碰巧符合的正體轉換指令；一般使用頻率本身不會改變 App 與指令之間的順序，明確設定的完整指令別名仍優先。單純打字、移動選取、取消或開啟失敗不會留下學習記錄，也不記錄剪貼簿內容、剪貼簿頁面的搜尋、Google 搜尋字詞，或 GPT 提問、翻譯與回答。資料只存本機，搜尋使用記憶體中的分數，背景更新不會讓正在選擇的列表突然跳動。

### Instant calculator / 即時計算

Type an arithmetic expression directly in Cue, such as **`1+2*3`**, **`(12+8)/4`**, or **`2^10`**. The answer appears as the first result while you type. Press **Return** while it is selected, or **Command+1**, to copy just the answer and close Cue; paste with **Command+V** wherever you need it. Ordinary app and command matches remain available below the answer. Calculation works fully offline and does not save the expression or result in search-learning history. See the [calculator guide](docs/calculator.md) for supported syntax and limits.

直接在 Cue 輸入算式，例如 **`1+2*3`**、**`(12+8)/4`** 或 **`2^10`**，答案會即時顯示在第一列。選取答案後按 **Return**，或直接按 **Command+1**，即可只拷貝答案並收起 Cue，再到需要的位置按 **Command+V** 貼上。符合的 App 與指令仍會列在下方。計算完全離線，不會將算式或結果存入搜尋學習記錄。支援語法與限制詳見[計算機說明](docs/calculator.md)。

### Unit and currency conversion / 單位與幣值換算

Type **`10m`**, **`5坪`**, or **`100USD`** for up to three common conversions, or specify a target with **`10m to ft`** or **`100USD to TWD`**. Press **Return** on a result or its **Command+number** to copy only the numeric value and close Cue. Physical units, including Taiwan's 坪, work offline. Currency conversion requires Cue's global network access: it uses a daily reference-rate table, shows its date and source, and hides currency answers when access is off. Amounts and query text stay on this Mac. See the [unit and currency guide](docs/unit-conversion.md) for supported units, freshness and privacy.

輸入 **`10m`**、**`5坪`** 或 **`100USD`**，即可看到最多三種常用換算；也可用 **`10m to ft`** 或 **`100USD to TWD`** 指定目標單位。選取結果後按 **Return**，或按對應的 **Command+數字**，只拷貝數值並收起 Cue。一般單位包含台灣的坪，完全離線。幣值換算需要允許 Cue 自行連網，使用每日參考匯率並顯示日期與來源；關閉網路就不顯示幣值答案。金額及查詢文字留在這台 Mac。支援單位、更新方式與隱私詳見[單位與幣值換算說明](docs/unit-conversion.md)。

### Google search / Google 搜尋

After the initial app index is ready, a nonempty launcher query with no matching app or command shows text actions: your Mac's **default browser** first, followed by GPT answers, translation, and the browsers you add. Press **Return**, click a result, or use **Command+1–9** to execute it. **Command+Return** searches the current text in the default browser even when local results exist; **Command+K** shows these text actions for the same text. In the normal result list, ordinary Return still executes the selected app or command. Blank input and input-method composition do not submit a search.

Type **`google settings`** or **`Google 搜尋設定`**, or press **Command+,** on a Google action, to open this feature's settings. Keep the system default and add or remove up to **eight browsers**; installed candidates appear only in the add interface and are never enrolled automatically. Each Mac keeps its own list. Browser search has a separate switch, **on by default**, and works even when Cue's own network access is off. Turning this feature switch off prevents new browser handoffs.

Typing remains local: Cue sends no live queries, requests no suggestions, and opens nothing until you execute a search. Google queries are not saved in Cue's search-learning history. Your browser and Google receive the submitted text. See the [Google search guide](docs/web-search.md) for browser choices and privacy, or [GPT answers and translation](docs/gpt.md) for the API actions.

初次 App 索引完成後，非空白文字若沒有符合的 App 或指令，就會顯示文字動作：第一個是這台 Mac 的**預設瀏覽器**，接著是 GPT 問答、翻譯與自行加入的瀏覽器。按 **Return**、點選結果或按 **Command+1–9** 執行。即使已有本機結果，也可按 **Command+Return** 使用預設瀏覽器搜尋，或按 **Command+K** 針對同一段文字顯示可用動作。一般結果列表中的 Return 仍執行選取的 App 或指令；空白輸入及輸入法組字期間不會送出搜尋。

輸入 **`google settings`**／**`Google 搜尋設定`**，或選到 Google 動作時按 **Command+,**，即可開啟此功能的設定。系統預設固定保留，另外最多可自行加入、移除**八個瀏覽器**；偵測到的 App 只出現在加入介面，不會自動加入搜尋列表。每台 Mac 保留自己的清單。瀏覽器搜尋有獨立開關，**預設開啟**，關閉 Cue 自己的網路仍可使用；關閉此功能開關才會阻止新的瀏覽器交接。

打字時只在本機處理，不會即時傳送查詢、取得搜尋建議或自行開啟瀏覽器。Google 搜尋字詞不會存入 Cue 的搜尋學習記錄；執行後的文字由瀏覽器及 Google 接收。瀏覽器選擇與隱私詳見 [Google 搜尋說明](docs/web-search.md)，API 動作見 [GPT 問答與翻譯](docs/gpt.md)。

### Link cleaner / 連結清理

Copy one HTTP or HTTPS link, invoke Cue, then type **`clean link`**, **`link cleaner`**, **`清理連結`**, or **`清理網址`** and execute the command. Cue removes recognized tracking parameters and replaces the clipboard with the cleaned link. It preserves other parameters, fragments, and their original encoding; ambiguous fields containing a literal semicolon are retained, and links with recognized signature parameters are left unchanged. The result reports how many parameters were removed, whether none can be safely removed or the link is protected, or why the clipboard could not be cleaned.

Cleaning runs entirely on this Mac, including with Cue's network access off. It does not open a browser, expand short links, follow redirects, or paste into another app. It reads and changes the clipboard only when you execute the command; a detected clipboard change while work is pending prevents replacement of the newer copy. Clipboard URLs are not added to search-learning history. This command needs no feature settings. See the [link cleaner guide](docs/link-cleaner.md) for supported links and limits.

複製一個 HTTP 或 HTTPS 連結後，叫出 Cue，輸入 **`clean link`**、**`link cleaner`**、**`清理連結`**或 **`清理網址`**並執行指令。Cue 會移除已知的追蹤參數，再將清理後的連結寫回剪貼簿；其他參數、網址片段及原有編碼保持不變。含未編碼分號、解析方式可能不同的欄位會保留，含已知簽章參數的連結則不修改。結果會顯示移除數量、沒有可安全移除的參數、受簽章保護，或無法清理的原因。

清理完全在本機執行，Cue 關閉網路時仍可使用；不會開啟瀏覽器、展開短網址、跟隨重新導向或貼到其他 App。只有執行指令才會讀取與修改剪貼簿；若處理期間偵測到剪貼簿已變更，就不取代較新的內容。剪貼簿網址不會加入搜尋學習記錄。此功能不需要額外設定；支援範圍與限制詳見[連結清理說明](docs/link-cleaner.md)。

### Emoji search / Emoji 搜尋

Type **`emoji`** or **`表情符號`** in Cue and open **Emoji Search**. Search by English or Traditional Chinese keywords, use **Up/Down** and **Return**, double-click a result, choose **Copy**, or press **Command+1–9** to copy a numbered emoji and close Cue. Paste into the destination app with **Command+V**; Cue does not paste automatically. **Esc** returns to the launcher. Results stay within nine rows without a scrollbar; refine the query to find another match.

The catalog and bilingual keywords are bundled with Cue. Search works fully offline, including first use, with no downloads or extra settings. See the [Emoji guide](docs/emoji.md) for the catalog and search behavior.

在 Cue 輸入 **`emoji`** 或 **`表情符號`**，開啟 **表情符號搜尋**。用英文或正體中文關鍵字搜尋，以**上下方向鍵**選取後按 **Return**、按兩下結果、按**拷貝**，或按 **Command+1–9**，即可拷貝編號對應的 emoji 並收起 Cue。到需要的位置按 **Command+V** 貼上，Cue 不會自動貼入。**Esc** 返回主搜尋。結果最多九列、不顯示捲軸；可縮小搜尋範圍來找其他結果。

圖示目錄與雙語關鍵字隨 App 內附，首次使用也完全離線，不需下載或額外設定。資料範圍與搜尋方式詳見 [Emoji 說明](docs/emoji.md)。

### GPT answers and translation / GPT 問答與翻譯

Enter text in Cue. If no local result matches, choose **Search Google**, **Ask GPT**, or **Translate with GPT**; **Command+K** offers these actions even when apps match. Google remains the first choice. Press the shown **Command+number** to run an action immediately. Added browsers remain available; with more than six, **Other Browsers…** opens the complete list.

Search **`gpt settings`**, or press **Command+,** on a GPT action or reply, to save your own OpenAI API key in macOS Keychain. Enable Cue's global network access to use GPT; typing alone never sends text. API usage is billed separately from a ChatGPT subscription. The default is **GPT-6 Luna**, with extra reasoning disabled for quick replies; the model ID can be changed in GPT Settings. Translation defaults to **Chinese → English; other languages → Traditional Chinese with Taiwan terminology**, with fixed Chinese or English options.

Replies stream into a compact, selectable text view. **Copy / Command+Return** copies the reply; **Stop** cancels generation; **Retry** explicitly starts a new request. **Esc** returns to the original text so you can choose Google instead. GPT has no live web search in this version; use Google for current information. GPT text is excluded from search learning. The separate, enabled-by-default [Command History](docs/command-history.md) saves submitted input locally; replies are not saved there. See [GPT setup, privacy and limits](docs/gpt.md).

在 Cue 輸入文字；沒有本機符合結果時，可選擇 **Google 搜尋**、**問 GPT** 或 **GPT 翻譯**。有 App 符合時也能按 **Command+K** 選擇，或用顯示的 **Command+數字** 立即執行。Google 保持第一個選項；自行加入的瀏覽器仍可使用，超過六個時會收進**其他瀏覽器⋯**。

輸入 **`gpt settings`**，或在 GPT 動作／回答頁按 **Command+,**，即可將自己的 OpenAI API 金鑰存進 macOS 鑰匙圈。GPT 需要允許 Cue 的全域網路存取；單純打字不會傳送文字。API 與 ChatGPT 訂閱分開計費。預設採用 **GPT-6 Luna**、關閉額外推理，也可在 GPT 設定更改模型。翻譯預設為**中文→英文，其他語言→正體中文（台灣用詞）**，亦可固定翻成正體中文或英文。

回答逐步顯示且可選取；按**拷貝／Command+Return**複製、按**停止**取消生成，或按**重試**重新送出一次。**Esc** 保留原始文字並返回，方便改用 Google。此版本 GPT 沒有即時網頁搜尋，最新資訊請用 Google。GPT 文字不加入搜尋學習；獨立且預設開啟的[指令歷史](docs/command-history.md)會將送出的輸入存於本機，不儲存回答。詳見 [GPT 設定、隱私與限制](docs/gpt.md)。

### Chinese conversion

Select text in an editable field, invoke Cue, type **`st`** for **Traditional Chinese with Taiwan vocabulary** or **`ts`** for **Simplified Chinese with mainland China vocabulary**, then press **Return**. Cue replaces the selection in the original app; use that app's **Command+Z** to undo.

Type **`chinese settings`** or **`簡繁設定`** to change these aliases. **Command+,** also opens this feature's settings while a conversion command is selected. Aliases take effect immediately and exact aliases rank first. Conversion runs fully offline, using bundled OpenCC dictionaries only when invoked; first use needs no download, and disabling network access preserves the same conversion behavior. macOS **Accessibility** permission is required for replacing another app's selection. See the [bilingual conversion guide](docs/chinese-conversion.md) for setup and supported fields.

在可編輯欄位選取文字後，叫出 Cue，輸入 **`st`** 轉為**正體中文（台灣用詞）**，或 **`ts`** 轉為**簡體中文（中國大陸用詞）**，按 **Return** 即可取代原本選取的文字；可在原 App 按 **Command+Z** 復原。輸入 **`簡繁設定`**，或在選到轉換指令時按 **Command+,**，即可自訂這兩個別名，儲存後立即生效。轉換完全離線，首次使用不需下載，關閉網路後仍使用相同詞庫與轉換規則；跨 App 取代需先允許 macOS「輔助使用」權限。

### Launch at login

Enable **Command+, → General & Interaction → Launch at login** to start your installed Cue automatically after signing in to your Mac. This is off for a new installation; Cue does not register itself automatically. The setting reflects macOS's existing registration. If approval is needed, use **Open Login Items…** and allow Cue in System Settings. You can disable it from Cue or macOS at any time. Keep the app at the same installed location when updating.

在 **Command+, → 一般與操作 → 登入時啟動** 開啟此選項，即可在登入 Mac 後自動執行已安裝的 Cue。新安裝預設關閉，不會自動註冊；設定會反映 macOS 中既有的註冊狀態。若需要授權，按**開啟登入項目⋯**，再到系統設定允許 Cue。可隨時從 Cue 或 macOS 關閉；更新時請維持相同安裝位置。

### Compact launcher and numbered results

Cue opens with just an empty input field: no initial results, placeholder, footer, settings button, or Escape hint. Start typing to find apps or commands; **Command+,** still opens Settings. The window grows with the result count and shows at most nine results, with no scrollbars. Refine the query to find another match. The result limit is fixed at nine.

Long input wraps to at most **two visible lines**, expanding the window vertically without changing its width. Longer text stays intact and scrolls with the caret. Shortening or clearing the input restores its compact height. **Return** still executes; **↑/↓** still select results or recall history.

長文字會自動換行，最多顯示**兩行**；視窗只增加高度，寬度維持不變。超過兩行的文字完整保留，並隨游標捲動；縮短或清空文字就恢復原本高度。**Return** 仍執行指令，**↑／↓** 仍用於選取結果或回看歷史。

A blue tint, inspired by Cue's icon, carries through the window and selected rows in both light and dark appearances. Larger input text and app names make results easier to read, with balanced spacing around the input. Built-in commands use white icons with blue line drawings and generous internal spacing. Conversion icons point right toward the target character 繁 / 简. Icons are prepared once in the background and cached; typing only reuses them.

內建指令採白底、藍色線條與充足留白；簡繁互轉的箭頭由左向右指向「繁／简」目標字。圖示只在背景產生一次並快取，打字時直接重用。

Every result has a number. **Command+1–9 executes the corresponding result immediately**: it opens an app, runs a command, or copies a clipboard item. These shortcuts act on the current result list and do not require a second Return press.

### Sleep, Lock Screen, and Screen Off

Type **`sleep`** or **`睡眠`** to put the Mac to sleep, or **`lock`** / **`鎖定`** to lock its screen. Press **Return** or the displayed **Command+number** to execute immediately. Cue closes first; neither command logs you out or closes your apps. See [system commands](docs/system-actions.md) for implementation and testing limits.

輸入 **`sleep`／`睡眠`** 可讓 Mac 進入睡眠；輸入 **`lock`／`鎖定`** 可鎖定螢幕。按 **Return** 或顯示的 **Command+數字** 即可立即執行，Cue 會先關閉視窗。兩者都不會登出或關閉其他 App；實作與驗證限制見[系統指令說明](docs/system-actions.md)。

Type **`screen off` / `display off` / `關閉螢幕`** to turn off the display immediately while the Mac keeps running. Password requirements on wake follow your macOS Lock Screen settings; use **Lock Screen** when you specifically want to lock the Mac.

輸入 **`screen off`／`display off`／`關閉螢幕`**，立即讓螢幕休眠，Mac 仍繼續運作。喚醒時是否要求密碼，依 macOS「鎖定畫面」設定；若目的是鎖定電腦，請使用**鎖定螢幕**。

### Window controls

Window controls are **on by default**, including when upgrading from a version without this feature; an explicitly saved off choice is preserved. **Option+M** opens a dedicated mode for the current window: **Option+arrows** for halves, **Command+arrows** to move displays, **Return** to fill the usable desktop, **Space** to center, **Tab** to restore, and **1–9** for your saved percentage layouts. Open **Window Settings…** from Cue’s menu bar, search `window settings`, or use the mode’s gear to change the shortcut and panel behavior. If another app occupies Option+M, this settings page shows the conflict and lets you choose a different shortcut.

All adjustments are local and require macOS Accessibility permission. On first use, or if an update invalidates the grant, Cue shows a permission guide instead of accepting ineffective layout actions. **Window Settings** shows the current status, a system-settings button, **Check Again**, and help for a stale enabled switch. Permission checks refresh when returning to that page; no permission prompt runs at startup. See [window controls](docs/window-controls.md) for setup, recovery, portable layout storage and testing limits.

視窗調整**預設啟用**，包含從尚無此功能的版本更新；曾手動關閉則保留原選擇。用 **Option+M** 調整目前視窗：**Option+方向鍵**半屏、**Command+方向鍵**跨顯示器、**Enter** 填滿可用桌面、**空白鍵**置中、**Tab** 還原，**1–9** 套用自訂比例配置。從 Cue 選單列選擇**視窗設定…**、搜尋 `window settings`／`視窗設定`，或點模式中的齒輪，可更改快捷鍵與面板行為。如果 Option+M 已被其他 App 使用，設定頁會顯示衝突，讓你更換快捷鍵。

操作完全離線，需 macOS 輔助使用權限。首次使用或更新後授權失效時，Cue 會顯示授權引導並停用無法執行的配置操作。**視窗設定**提供實際權限狀態、系統設定入口、**重新檢查**，以及開關已開但授權失效的處理方式；回到該頁會更新狀態，不在啟動時跳出系統授權提示。詳見[使用與授權說明](docs/window-controls.md)。

### Clipboard History

Type `clipboard` or `剪貼簿` in Cue, select **Clipboard History**, and press Enter. Recording is off initially; choose **Enable Clipboard History** to start saving new text and link copies on this Mac.

Saved history remains visible when its search field is empty. Each record shows its number and copied date and time, and the window adapts to the number of results. It shows the nine most recent matching records with no scrollbars; searching still covers all saved history, and this display limit does not delete older records. Search the history, select an item, and press **Return** to copy it, or use **Command+1–9** to copy a numbered result immediately. Then use **Command+V** in the destination app. Press **Delete/Backspace** to remove the selected item when the search field is empty; otherwise these keys edit the search text. The **Delete** button or **Command+Backspace** also removes a selected item from filtered results.

Use **Preview** or **Command+Y** to read the selected record in full without copying it; **Esc** returns to the list.

按**預覽**或 **Command+Y** 可閱讀所選記錄的完整內容，不會拷貝到剪貼簿；按 **Esc** 回到列表。

The page's gear or **Command+,** opens its own recording and retention settings. Retention defaults to **7 days**, with choices from **1 hour** to **No time limit**. History is stored as readable text on this Mac, up to **500 items or 4 MiB**. **Esc** returns from these settings to history, then from history to the launcher.

See the [Clipboard History guide / 剪貼簿記錄說明](docs/clipboard.md) for retention, storage limits, and privacy details, and the [clipboard search benchmark](docs/performance.md) for reproducible performance measurements.

### Settings backup & transfer / 設定備份與移轉

Open **Settings → Backup & Transfer** to export or import portable preferences, aliases, chosen browsers and window presets. Imports show a selectable preview and preserve this Mac’s network, recording, startup and permission choices. Ordinary JSON excludes API keys; optional password protection can carry a key only when you explicitly choose it. Passwords require at least 12 characters and are never saved. See the [backup guide](docs/settings-portability.md).

在**設定 → 備份與移轉**匯出或匯入偏好、別名、指定瀏覽器與視窗配置。匯入前可預覽並選擇要套用的區塊，保留這台 Mac 的網路、記錄、登入啟動與權限選擇。一般 JSON 不含 API key；選擇密碼保護後，才可另外勾選攜帶金鑰。密碼至少 12 個字元，Cue 不會儲存密碼。詳見[備份說明](docs/settings-portability.md)。

## Command history / 指令歷史

On an empty launcher, press **↑** for previous executed inputs and **↓** for newer ones. Editing ends recall; ordinary search keeps its result-selection arrows. **Return** runs the recalled action. Type **`history`** or **`指令歷史`** for a searchable list with deletion, paging and its own recording settings.

History includes submitted Google/GPT text, calculations, filename queries and local commands. Recording is on by default, saved only on this Mac, bounded to 200 entries / 30 days, and separate from search-learning data. Responses and clipboard contents are excluded. See [history controls, limits and storage](docs/command-history.md).

空白輸入欄按 **↑／↓** 回看已執行的輸入，修改文字就結束回看，**Return** 執行原本動作。輸入 **`history`** 或**「指令歷史」**可搜尋、刪除及翻頁，並在該頁齒輪關閉記錄或清空。預設記錄已送出的 Google／GPT 文字、計算式、檔名查詢與本機指令，只存本機，最多 200 筆／30 天；不記錄回答或剪貼簿內容，也不加入搜尋排序學習。詳見[操作、容量與儲存說明](docs/command-history.md)。

## Build and install from source

Prefer building your own app? **Command Line Tools with Swift 6 or later are enough; full Xcode is optional.** If the tools are not installed, run `xcode-select --install` and wait for installation to finish. Then quit any running Cue and run:

```sh
git clone https://github.com/hsiuhsiu/cue.git
cd cue
./scripts/install-app.sh
open "$HOME/Applications/Cue.app"
```

This builds an optimized **Release** app for your Mac and installs it permanently at **`~/Applications/Cue.app`**, without a paid developer account, signing key, or administrator access. Existing settings, clipboard history, and search learning are preserved. The script uses Swift Package Manager, bundles all resources and the updater, and signs the app locally. The first build downloads the pinned Sparkle 2.10.0 dependency. Installation keeps Cue on disk after reboot; **Launch at login** also starts it for you.

To update, quit Cue, run `git pull --ff-only` and `./scripts/install-app.sh` in this repository, then open the installed app again. Source builds default to Cue's own network access and automatic update checks **off**. An explicit network choice saved in Settings is preserved across installs. You can enable network access to use the updater, but installing an update offered by Cue replaces your build with the published GitHub app. Explicit browser search has its separate, enabled-by-default setting.

也可以自行編譯，無須下載 DMG。**只需含 Swift 6 以上的 Command Line Tools，不必安裝完整 Xcode**。若尚未安裝，執行 `xcode-select --install` 並等安裝完成；結束正在執行的 Cue，再執行上方指令，即可建置 Release 版本並固定安裝至 **`~/Applications/Cue.app`**，不需付費開發者帳號或管理者權限。腳本會自動編譯、打包與簽章；現有設定、剪貼簿記錄與搜尋學習資料會保留。首次建置需連線下載固定版本的 Sparkle；自行建置版預設關閉 Cue 自己的網路與自動檢查更新，設定中明確儲存的網路選擇則會保留。之後可用 `git pull --ff-only` 與安裝腳本更新；若自行允許網路並從 Cue 安裝更新，會換成 GitHub 發布的 App。明確操作的瀏覽器搜尋有獨立、預設開啟的設定。

See the [English / 正體中文 source installation guide](docs/building.md) for updating, custom install locations, tool setup, build-only and Debug options. `./scripts/build-app.sh --check` checks prerequisites without building. You can also open `Cue.xcodeproj` and run the **Cue** scheme for development.

## Network access

Use **Settings → Network & Updates → Allow Cue to access the network** to control network requests made by Cue itself. Source builds—including SwiftPM, Xcode Debug/Release, and the local build/install scripts—default to **off**; official release DMGs default to **on**. Missing build metadata means off. An explicit choice saved in Settings takes precedence and survives updates, reinstalls, and switching between source and published builds.

Turning network access off disables both manual and automatic update checks and downloads. It also stops GPT requests and currency-rate work and hides currency answers, including cached ones. The automatic-check toggle displays **off** and is disabled while offline, but Cue remembers its separate preference and can resume the chosen schedule when access is allowed again. Local app/command search, Clipboard History, system commands, Chinese conversion, link cleaning, emoji search, the calculator, and physical-unit conversion remain fully available. Explicit Google searches use a separate browser-search switch in **Google Search Settings**, on by default; the browser handles those network requests. See [network behavior and scope](docs/network-policy.md).

在**設定 → 網路與更新 → 允許 Cue 自行連網**管理 Cue 自己發出的網路請求。原始碼建置（包含 SwiftPM、Xcode Debug／Release 與本機建置／安裝腳本）預設**關閉**，正式下載的 DMG 預設**開啟**；缺少建置資料也視為關閉。在設定中明確儲存的選擇優先，更新、重新安裝或切換自行建置與下載版都會保留。

關閉網路會停用手動、自動檢查更新及下載；也會停止 GPT 請求與匯率工作，並隱藏幣值答案，包含已有快取的情況。自動檢查開關會顯示**關閉**且無法操作，但原先的偏好仍會保留，重新允許網路後可依原設定恢復排程。本機 App／指令搜尋、剪貼簿記錄、系統指令、簡繁轉換、連結清理、emoji 搜尋、計算機與一般單位換算仍可完整使用。明確執行的 Google 搜尋由瀏覽器連線，受 **Google 搜尋設定**內獨立且預設開啟的瀏覽器搜尋開關控制；詳見[網路行為與適用範圍](docs/network-policy.md)。

## Updates

With network access allowed, use **Check for Updates…** from the menu bar or **Command+, → Network & Updates**. Automatic checks are enabled by default for a fresh official DMG installation, normally once every 24 hours; source builds default to off. Existing automatic-check preferences are preserved. Turning off automatic checks leaves manual checks available while network access is allowed. Scheduled updates only change the menu bar indicator and update entry; they do not take focus from typing. The user chooses whether to download and install, then uses **Install and Relaunch** to finish.

Sparkle verifies signed update archives and the signed HTTPS appcast against the public key embedded in Cue. Checks contact GitHub; no usage analytics or system profile is sent. Updates run independently of launcher input. Sparkle's license is included in the app bundle and in [Resources/Sparkle-LICENSE.txt](Resources/Sparkle-LICENSE.txt).

## Package a release

Versions distinguish source milestones such as **`1.1.1-beta.1`** from stable
releases such as **`1.1.1`**, without an internal build number in parentheses.
Xcode's **Release** configuration means optimization; a beta source build stays
a beta. Use `scripts/set-version.sh` to advance a milestone and its internal
update build together. The release script accepts stable metadata only. See
[versioning](docs/versioning.md); a local beta label does not publish a GitHub preview.

版本區分 **`1.1.1-beta.1`** 等開發里程碑與 **`1.1.1`** 等正式版，不再把內部
建置編號放在主要版號後的括號。Xcode **Release** 代表最佳化，beta 原始碼仍是
beta。用 `scripts/set-version.sh` 同步更新版號與內部 build；正式打包只接受
stable 資料。本機 beta 標記不會建立 GitHub 預覽版，詳見[版本規則](docs/versioning.md)。

```sh
./scripts/release.sh
```

The local release script reads the version from `Resources/Info.plist`, builds a universal app, and writes `Cue-<version>-universal.dmg`, a signed `appcast.xml`, and `SHA256SUMS.txt` under `.build/releases/<version>/`. It enables Cue-owned networking and automatic-check defaults only in the final staged release app before signing; source and ordinary build output keep those defaults off. Publishing requires the maintainer's update-signing key in Keychain; ordinary source builds and tests do not. The script prepares files locally and never uploads them. Developer ID signing and notarization are not part of this pipeline. See [publishing a release](docs/releasing.md) for publication order and key management.

## Tests

```sh
./scripts/check-version-tests.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./scripts/check-settings.sh
./scripts/check-settings-layout.sh
./scripts/check-login-item.sh
./scripts/check-launcher-keyboard.sh
./scripts/check-command-history.sh
./scripts/check-web-search.sh
./scripts/check-link-cleaner.sh
./scripts/check-emoji.sh
./scripts/check-calculator.sh
./scripts/check-unit-conversion.sh
./scripts/check-currency-rates.sh
./scripts/check-command-icons.sh
./scripts/check-adaptive-search.sh
./scripts/check-app-aliases.sh
./scripts/check-gpt.sh
./scripts/check-gpt-settings.sh
./scripts/check-gpt-ui.sh
./scripts/check-clipboard.sh
./scripts/check-system-actions.sh
./scripts/check-window-service.sh
./scripts/check-window-settings.sh
./scripts/check-window-mode.sh
./scripts/check-settings-backup.sh
./scripts/check-backup-ui.sh
./scripts/check-selected-text.sh
./scripts/check-conversion-lifecycle.sh
./scripts/check-network-policy.sh
./scripts/check-build-network-policy.sh
./scripts/check-source-app.sh
./scripts/check-updates.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/check-localizations.swift .build/Cue.app
```

The settings check exercises the actual `CueSettings` store: bounded change notifications, saving edits, and reloading preferences. It uses an isolated temporary preferences domain and leaves the app’s settings untouched.

The source-app check validates a built `.build/Cue.app`, copies it to a temporary path containing spaces, and checks signatures, portable framework paths, both languages, icons, emoji data and offline Chinese conversion. A separate probe loads the embedded Sparkle without starting its updater. It never launches the production app or changes an installed copy.

Prefer these isolated checks for day-to-day development. They use synthetic inputs, temporary preferences, private pasteboards, injected services, and offscreen native views. Run costly checks sequentially. Do not replace or stop the installed Cue, send desktop keystrokes, or use personal history, credentials, or the system clipboard as test fixtures. Coordinate manual desktop tests separately when verifying global activation, OS permission prompts, cross-app text replacement, or perceived input-to-display latency.

The settings-layout check renders English and Traditional Chinese settings offscreen, including offline and error states, and verifies close callbacks without activating windows or accessing real credentials. Set `CUE_SETTINGS_PREVIEW_DIRECTORY` to a local directory to save PNG previews. It needs the already-resolved, pinned Sparkle framework; it does not download dependencies or contact update servers.

The backup checks use synthetic settings, temporary files and fake key stores to verify selected merges, rollback, clipboard-retention consent, encrypted exports and credential restoration failures. `SettingsBackupTests` also covers published password-derivation vectors, wrong passwords, tampering and bounded file parsing. No real API key or personal history is read.

The login-item check uses an injected macOS service to verify enabling, disabling, approval-required states, errors, and refresh behavior without changing system login items.

The settings check also verifies per-app language overrides, relaunch persistence, restoring the system preference, and preserving existing shortcuts. The localization check compares all English/Traditional Chinese keys and format arguments, language fallback, and resources inside a built app. Omit the app path to check only source tables. Verify both languages in a Release build, including Settings layout, menu items, shortcut recording/canceling, Chinese command search, and Command-comma focus; restore **Follow System** after testing.

The optimized launcher keyboard check exercises the real AppKit view without an app-menu fallback, including Command-comma, explicit web search, modifiers, repeat events, marked-text composition, two-line input sizing and editing beyond that visible limit. Set `CUE_INPUT_PREVIEW_DIRECTORY` to save light/dark multiline previews. It verifies shortcut routing and offscreen editing, not application activation, and does not show windows or change user preferences.

The web-search check uses isolated preferences and injected browser openers to verify fallback, original query encoding, browser choices, feature settings, and the separation between Cue-owned networking and external browser handoffs. It does not send real searches or alter the system default browser.

Link-cleaning and emoji checks use synthetic fixtures and private pasteboards to exercise copying, cancellation, keyboard routing, and local search without reading or replacing the operator's clipboard.

The calculator check uses synthetic expressions, private pasteboards, and injected copy operations to verify inline results, powers, copying, cancellation, keyboard routing, and offline behavior without changing the operator's clipboard.

The currency-rate check uses an injected transport, clock, isolated preferences and a temporary cache to verify network gating, cancellation, fresh-only rates and retry limits. It makes no live API request and does not use the real currency cache.

For an optional live-provider smoke check, explicitly run `./scripts/check-currency-live.sh --live`. This sends one fixed USD-table request using an isolated enabled policy and no disk cache; it does not change Cue's saved network preference.

The unit-conversion check exercises launcher results, numeric copying, rate changes and cancellation with synthetic queries, injected rates and a private pasteboard.

The adaptive-search check covers successful and failed launches, command learning, stable visible rows during background updates, cache invalidation, and persistence across restarts using injected actions and isolated synthetic state. It never sleeps or locks the Mac or reads real usage history.

`./scripts/benchmark-long-query.sh` measures optimized model updates for unusually long synthetic input; `--baseline-ref <git-ref>` compares a previous revision without changing the checkout. Text beyond 1,024 UTF-8 bytes skips application/command matching and keeps the original input available for text actions. These are computation measurements, not visible interaction latency.

`./scripts/benchmark-interactions.sh` measures native query/result layout, history recall and actual field-editor insertions in an invisible panel, including long text. Its `--source-root` option uses another source snapshot for comparison. These isolated measurements exclude OS key delivery and display composition.

The system-actions check uses injected actions to verify Sleep, Lock Screen, and Screen Off through the real controller without changing the Mac's power or lock state. Native service details and manual verification limits are documented in [system commands](docs/system-actions.md).

The optimized clipboard check covers capture, filtering, persistence, retention, full-text preview, rapid query/copy/delete interactions, cancellation while entering settings or leaving the page, and feature-local keyboard settings. It uses synthetic text on private named pasteboards and isolated preferences; it never reads the system clipboard.

The selected-text check uses a synthetic accessibility driver and private pasteboards to verify selection validation, one-shot replacement, cancellation, acknowledgement, and clipboard restoration. Dictionary tests and the [OpenCC reference verifier](docs/chinese-conversion-data.md) check conversion separately; native app replacement still needs a manual test with Accessibility enabled.

The network-policy check uses isolated preferences to verify source/release defaults, missing or malformed metadata, saved choices, and immediate change notifications. The build-policy check verifies the source plist; use `source <app-or-plist>` or `official <app-or-plist>` to validate a built bundle's defaults. The updater check exercises offline startup, manual and scheduled checks, cancellation, and preference restoration with an injected update engine.

Verify Settings focus in a Release build: with another app active, invoke Cue, type a query, and press Command-comma. Settings must appear in front with an active title bar and keyboard focus, without another click. Repeat with Settings already open behind another app, after closing it, and after minimizing it. Switching away afterward must not pull focus back to Cue.

Or run the **Cue** scheme's tests in Xcode / from the command line:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Cue.xcodeproj -scheme Cue -destination 'platform=macOS' \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO test
```

`CueCore` holds discovery, search, and preference validation independently of presentation. `Sources/Cue` uses AppKit for the latency-sensitive launcher and SwiftUI for Settings. The launcher reuses native table rows, loads and decodes icons in the background, caches recent searches, and sets focus synchronously. Tests cover ranking, discovery, and preferences. See [performance design and reproducible measurements](docs/performance.md) for workload definitions and validation limits; component timings are not end-to-end latency guarantees.

## Controls

| Control | Action |
| --- | --- |
| Option+Space (default, configurable) | Show or hide Cue |
| Command+, | Open Settings from Cue's launcher |
| Up / Down | Select a result |
| Enter | Launch the selected application or run the selected command |
| Command+Return | Search the current main-launcher text with Google in the default browser / 在預設瀏覽器以 Google 搜尋主視窗文字 |
| Command+E | Edit the selected app’s search alias / 編輯所選 App 的搜尋別名 |
| Command+K | Choose Google, GPT answers, or GPT translation for the current text / 針對目前文字選擇 Google、GPT 問答或翻譯 |
| Command+1–9 | Immediately execute the numbered result; in Clipboard History or Emoji Search, copy it and close Cue |
| Escape | Return from Clipboard History or Emoji Search to the launcher; dismiss Cue from the launcher |
| Menu bar → Show Cue / Settings… / Quit Cue | Open the launcher, configure Cue, or exit |

Type `reindex`, `update index`, `refresh apps`, or `更新索引` to find **Update App Index**, then press Enter. Cue scans again in the background, keeps the launcher usable, and shows the updated application count when finished. You can install or remove applications and refresh without restarting Cue.

Press **Command+,** in the launcher (or choose the menu-bar Settings item) to configure the global shortcut, pointer/main display placement, dismissal on focus loss, launch at login, language, network access, and update checks. On a GPT action or reply, **Command+,** opens GPT Settings. On a Google action, **Command+,** opens Google Search Settings; inside Clipboard History, its gear and **Command+,** open clipboard-specific settings. Preferences are saved immediately and persist across restarts; language changes take effect when Cue reopens. If a new shortcut conflicts, Cue keeps the previous working shortcut. Cue reserves its action, result-number, and standard text-editing shortcuts so a custom global shortcut cannot take them over.

Pressing Enter on an app dismisses Cue immediately; launch failures reopen the query with an error. The default placement follows the mouse pointer. The index is built at startup; use Update App Index after installing or removing applications. Show Cue remains available from the menu bar if another app occupies the saved shortcut.

To verify the interface manually, invoke Cue from another app, type `saf` or `term`, change selection with the arrow keys, and launch with Enter. Invoke Cue again to check that the query is empty, then test Escape, shortcut toggling, light/dark appearance, and placement on another display.

## License / 授權

Cue is available under the [MIT License](LICENSE). Bundled third-party components and data retain their own licenses: [Sparkle](Resources/Sparkle-LICENSE.txt), [OpenCC](Sources/Cue/Resources/OpenCC-LICENSE.txt), and [Unicode / CLDR](Sources/Cue/Resources/Unicode-LICENSE.txt).

Cue 採用 [MIT 授權](LICENSE)。內附的第三方元件與資料維持各自的授權：[Sparkle](Resources/Sparkle-LICENSE.txt)、[OpenCC](Sources/Cue/Resources/OpenCC-LICENSE.txt) 與 [Unicode／CLDR](Sources/Cue/Resources/Unicode-LICENSE.txt)。
