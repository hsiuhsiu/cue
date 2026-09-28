# Google search / Google 搜尋

## English

Available in Cue 0.6.0. Search with your Mac's default browser or browsers
you explicitly add in Google Search Settings. Translation is not implemented.

### Search from the launcher

1. Invoke Cue with Option+Space and type your query.
2. After the initial app index has loaded, a nonempty query with no matching app
   or built-in command shows Google search actions: the system default first,
   followed by your added browsers. Press **Return**, click a result, or use
   **Command+1–9** to search with that browser.
3. If there are local results but you want Google, press **Command+Return** to
   use the system default, or **Command+K** to show the browser search actions
   for the text already entered. Ordinary Return still executes the selected
   app or command while the normal local result list is showing.

The default browser is the one configured in macOS, so each computer can use its
own browser without changing Cue's default action. Google search applies to the main launcher;
searches inside Clipboard History or Emoji Search stay within those local catalogs. Blank input does
nothing, and shortcuts do not submit input-method composition before it is
committed. Cue closes when it hands the search to the browser.

### Google Search Settings and browser choices

Type **`google settings`**, **`browser settings`**, or **`Google 搜尋設定`** and
open **Google Search Settings**. **Command+,** opens the same feature settings
when a Google action is selected. These options stay out of Cue-wide Settings.

The system default is always the first action and cannot be removed. Add up to
**eight browsers** to keep every action within the nine numbered results. The
Add Browser interface discovers installed apps that can open HTTPS links; only
the browsers you explicitly add appear in search actions. Detection does not
automatically enroll every installed browser. Remove a browser from this list
to stop showing its action; it does not uninstall the app.

Search actions show a small badge from the installed browser’s app icon. The default action follows the current macOS default browser; unavailable icons keep the plain search artwork. Icons are prepared locally in the background and cached.

The list is saved on this Mac. Browsers are identified by bundle identifier,
not an installation path, and another Mac can have its own list. A saved choice
that is no longer available produces an error instead of silently sending the
query through a different browser. Browser discovery runs in the background
when these settings open or you choose Add Browser, not on each keystroke.

### Network access and privacy

The **Enable Google search** switch in **Google Search Settings** is **on by
default** for source and published builds. Its saved choice is independent of
**Settings → Network → Allow Cue to access the network**, which governs requests made by
Cue itself, including update checks. You can leave Cue's own networking off
and still explicitly send a search to your browser. Turn off browser search in
the feature settings to prevent those handoffs as well.

Cue does not fetch search suggestions, preview results, or send queries while
you type. It creates a Google search URL only for the action you execute and
checks the browser-search setting immediately before opening it. When that
setting is off, search actions explain why they are unavailable and do not open
a browser. Cue does not save the
Google query in its search-learning history. Your browser and Google receive
the submitted query and use their own history, account, and privacy settings.
After handoff, changing either Cue setting cannot stop that browser's
navigation or recall text already sent. See the [network policy](network-policy.md).

### Later text actions

**Command+K** currently offers Google search with your configured browsers.
Translation and other text actions remain future directions; this feature does
not contact a translation or AI service. Any future API request made by Cue
must obey the global network setting. See [future directions](future-directions.md).

## 正體中文

自 Cue 0.6.0 起提供。可用這台 Mac 的
預設瀏覽器，或在 Google 搜尋設定中自行加入的瀏覽器搜尋。翻譯動作尚未實作。

### 從主視窗搜尋

1. 按 Option+Space 叫出 Cue，輸入要搜尋的文字。
2. 初次 App 索引載入後，若非空白查詢沒有符合的 App 或內建指令，就會顯示
   Google 搜尋動作：第一個是系統預設，接著是你自行加入的瀏覽器。按
   **Return**、點選結果或按 **Command+1–9**，用對應瀏覽器執行搜尋。
3. 若已有本機結果，但你想搜尋 Google，按 **Command+Return** 使用系統預設，
   或按 **Command+K** 針對已輸入文字顯示瀏覽器搜尋動作。顯示一般本機結果時，
   普通 Return 仍執行選取的 App 或指令。

瀏覽器依 macOS 設定的預設值開啟，因此每台電腦可以使用自己的預設瀏覽器，
不必更改 Cue 的預設動作。Google 搜尋適用於主視窗，剪貼簿與 Emoji 頁面的搜尋仍只篩選各自的本機資料。
空白輸入不會執行搜尋，輸入法尚在組字時，快速鍵也不會將文字送出。Cue 將
搜尋交給瀏覽器時會收起視窗。

### Google 搜尋設定與瀏覽器選擇

輸入 **`google settings`**、**`browser settings`** 或 **`Google 搜尋設定`**，
開啟 **Google 搜尋設定**。選到 Google 搜尋動作時按 **Command+,** 也會開啟
這個功能的設定，不會把這些選項塞進 Cue 的整體設定。

系統預設固定在第一項，不能移除；另外最多可加入 **八個瀏覽器**，讓所有動作
都能用九個編號直接選擇。「加入瀏覽器」介面會偵測已安裝且能開啟 HTTPS 連結
的 App，但只有你明確加入的瀏覽器才會出現在搜尋動作中，不會自動加入所有
偵測結果。移除清單中的瀏覽器只會隱藏該動作，不會解除安裝 App。

搜尋動作會在圖示右下角顯示瀏覽器的小圖示；系統預設項目對應目前 macOS 的預設瀏覽器。取不到圖示時保留一般搜尋圖示。圖示只從本機在背景載入並快取。

清單儲存在這台 Mac，以 bundle identifier 辨識瀏覽器，不綁定安裝路徑；另一台
Mac 可設定自己的清單。若原本加入的瀏覽器已無法使用，會顯示錯誤，不會悄悄
換成其他瀏覽器送出文字。開啟功能設定或按「加入瀏覽器」時，才會在背景偵測，
不會在每次打字時執行。

### 網路存取與隱私

**Google 搜尋設定**內有獨立的**啟用 Google 搜尋**開關，自行建置與發布版都
**預設開啟**，已儲存的選擇會保留。**設定 → 網路 → 允許 Cue 自行連網**控制的是 Cue 自己發出的
請求，包含檢查更新；因此可關閉 Cue 自己的網路，同時保留明確操作後交給
瀏覽器的搜尋。若也要阻止這種交接，請關閉功能設定中的瀏覽器搜尋。

Cue 不會在打字時取得搜尋建議、預覽結果或傳送查詢。只有執行動作時才建立
Google 搜尋網址，並在開啟前再次確認瀏覽器搜尋開關。該開關關閉時，搜尋動作
會說明停用原因，不會開啟瀏覽器。Google 搜尋字詞不會存入 Cue
的搜尋學習記錄。送出的文字由瀏覽器及 Google 接收，依各自的歷史記錄、帳號
及隱私設定處理。交給瀏覽器後，更改 Cue 的任一開關都無法停止該瀏覽器的導覽，也
無法收回已傳出的文字。詳見[網路政策](network-policy.md)。

### 之後的文字動作

**Command+K** 目前提供使用已設定瀏覽器的 Google 搜尋。翻譯及其他文字動作
仍屬未來方向，此功能不會連到翻譯或 AI 服務。未來若由 Cue 自己發出 API
請求，必須遵守全域網路開關。詳見[未來方向](future-directions.md)。
