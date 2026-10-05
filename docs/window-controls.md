# 視窗調整 / Window Controls

以獨立鍵盤面板調整目前視窗的位置與大小，保持主搜尋快速、簡潔。所有操作在本機完成，使用 macOS 輔助使用權限，不需要網路或第三方視窗管理套件。

## 開始使用

安裝含此功能的版本後，視窗調整**預設啟用**；從尚無此功能的舊版本更新也一樣，已儲存的關閉選擇則會保留。回到要調整的 App，按 **⌥M**，或在 Cue 輸入 `window`／`視窗`。從 Cue 選單列選擇**視窗設定…**、搜尋 `window settings`／`視窗設定`，或在視窗模式按 **⌘,**／齒輪可進設定。

Cue 需要 macOS「輔助使用」權限。未授權時，視窗模式會顯示授權說明與引導入口，配置按鈕暫停使用；此時按 **Return** 可開啟引導。只有明確按下系統設定入口時才要求系統提示授權；不在啟動時索取權限。若快捷鍵已被占用，該次啟動暫不註冊視窗快捷鍵，保留已存設定與 Cue 主搜尋；請從選單列的**視窗設定…**查看原因並更改快捷鍵。

### 新安裝與更新後的授權

1. 在**視窗設定 → 權限**查看目前這份 Cue 的實際狀態。已授權者可直接使用，包含先前為簡繁轉換授予、目前仍有效的權限；Cue 不會因更新就一律要求重新授權。
2. 若未授權，按**開啟系統設定**入口，在「隱私權與安全性 → 輔助使用」允許 Cue。macOS 27 的英文頁面名稱為 **Device Control and Data Access**；入口會直接開啟對應頁面。[Apple 授權說明](https://support.apple.com/guide/mac-help/mh43185/mac)
3. 回到 Cue 的視窗設定，狀態會重新檢查，也可按**重新檢查**。看到已允許後，回到目標 App 再按目前設定的快捷鍵（預設 **⌥M**）。若原本從視窗模式進設定，關閉設定會重新擷取原目標，但不執行授權前按過的指令。

若系統開關已開啟，Cue 卻仍顯示未授權，展開設定中的排解說明。更新、自行重建或不同安裝位置可能留下不適用於目前執行檔的授權。先將 Cue 開關關閉再開啟；若仍失敗，在系統清單移除舊的 Cue，再加入**目前正在執行的這份 Cue.app**。設定頁可在 Finder 顯示目前 App，避免選到 DMG、舊副本或建置目錄的另一份。必要時結束並重新開啟同一份 App，再檢查。Cue 不會自行清除權限或替使用者授權；不要為了重試又重建 App。

**English:** Window controls default to on for fresh installs and upgrades without a saved window configuration; a saved off choice is preserved. Start with **Option+M**, or use Cue’s menu-bar **Window Settings…** entry if the shortcut is occupied. Missing permission leads to a guide with the current grant status, a system-settings button and **Check Again**. The OS page is **Privacy & Security → Accessibility**, named **Device Control and Data Access** in macOS 27. Returning to Window Settings refreshes the status without polling. Existing valid permission is reused; updates never assume an old grant is still valid. If the switch is on but Cue remains untrusted, toggle Cue off/on, then remove the stale Cue entry and add the current app if needed. Use the page’s Finder action to locate the running app; restart that same app if required. After granting, select the target window and invoke the configured shortcut again. Closing a guide opened from window mode recaptures the original target without replaying earlier actions. Cue never grants or resets permissions itself, and ordinary startup shows no permission prompt.

在**視窗設定 → 數字預設**新增 1–9：輸入名稱及距離左／上邊界、寬／高的百分比，例如左 60% 為 X=0、Y=0、寬=60、高=100。按**儲存配置**才套用。也可先對目標叫出視窗模式，再進設定使用已驗證的目標位置；操作仍在進行、目標失效或超出可用範圍時，不提供可能過期的快照。

**調整後保留面板**可以隨時開關。關閉時，半屏、填滿、置中、還原及數字配置成功後會關閉面板；跨螢幕保留。開啟後所有動作都保留面板，按 Esc 離開。有大小限制或部分成功的提示也會保留，避免隱藏結果。

## 儲存與移轉

設定存放於 `~/Library/Application Support/com.yyhsiu.cue/WindowControls/settings.json`，包含格式版本、啟用開關、快捷鍵、面板行為及最多九個比例配置。檔案以背景原子寫入保存、限制讀取大小並驗證內容。寫入失敗會顯示提示與重試入口；尚未保存的修改只在目前執行期間有效。檔案不含 API key、視窗標題、螢幕 ID 或操作歷史。

跨 Mac 移轉請使用 **Cue 設定 → 備份與移轉**，匯出後在另一台選擇匯入「視窗調整與配置」。預覽會列出快捷鍵、面板行為與比例配置，保留目的 Mac 的啟用開關並檢查快捷鍵衝突；備份未列出的數字配置也會保留。系統權限仍需在目的 Mac 個別授予。完整設定與可選的密碼加密金鑰備份，詳見[備份移轉說明](settings-portability.md)。

## 模式與範圍

Cue 提供獨立的「視窗調整模式」，預設用 **⌥M** 叫出。也能從 Cue 主搜尋輸入 `window`／`視窗` 進入同一模式。使用同一份 App、設定資料與權限，保持主搜尋的畫面及打字路徑不變。

這項功能**預設啟用**，成功讀取設定並註冊快捷鍵後即可用 ⌥M。已儲存的關閉選擇保持不變；關閉時立即釋放快捷鍵、取消待處理動作。停用時主搜尋入口顯示功能設定，讓使用者再次啟用。權限仍由使用者明確授予，預設啟用功能不代表取得控制其他 App 的權限。既有 ⌥Space 與主搜尋不受影響。

專用模式適合這組固定、連續的鍵盤操作：不必每次先搜尋指令，也不會讓數字預設和主搜尋的 ⌘數字選取混在一起。所有操作離線完成；不需要 OpenAI、其他 API 或第三方套件。

## 鍵盤操作

Enter 填滿可用桌面；數字預設只控制目前單一視窗。面板保留方式由功能設定控制。

| 輸入 | 行為 |
| --- | --- |
| ⌥M | 叫出／關閉視窗模式；設定中可更改啟動快捷鍵。 |
| ⌥←／→／↑／↓ | 目前顯示器的左／右／上／下半屏。每次都是明確的半屏，不加入連按四分之一屏等隱藏規則。 |
| ⌘←／→／↑／↓ | 移到該方向的另一個顯示器。沒有目的顯示器時不移動，顯示簡短提示。 |
| Return／Enter | **填滿可用桌面**：保留選單列與 Dock 所需空間，不進入 macOS 的獨立全螢幕 Space。 |
| Space | 在目前顯示器的可用範圍水平、垂直置中，保持大小；過大的視窗以可達標題列為優先。 |
| Tab | 回到這個視窗上一次由 Cue 操作前的大小、位置與顯示器；再次執行可在最近兩個狀態間切換。 |
| 1–9 | 套用使用者儲存的尺寸與位置，例如左 60%／右 40%。每個數字作用於**當前單一視窗**；未設定的數字不執行。 |
| Esc | 關閉模式、保留已完成的調整，不另外回復視窗。 |
| ⌘, | 開啟這項功能自己的設定。 |

## 模式與畫面

- 以小型原生浮動面板顯示目標 App、簡單的顯示器／視窗示意及按鍵提示。沿用 Cue 淡藍色重點色、留白與線條圖示，不加入搜尋框、全桌面遮罩或進出動畫。示意圖由幾何資料繪製，不擷取畫面。
- 動作直接執行，不再按一次 Enter 確認。預設半屏、置中、填滿、還原、數字預設成功後即關閉並返回原 App；**移動顯示器先保留模式**，方便接著按 ⌥方向調整。開啟「調整後保留面板」可讓所有動作保留模式。
- 多次命令以序列處理，後續幾何以已確認的實際結果為準。不用 debounce 等待使用者停止輸入。相同半屏等冪等動作的鍵盤自動重複可忽略；Tab、數字與啟動鍵的自動重複一律忽略，避免反覆切換。
- Cue 先記錄啟動前的來源 App，面板取得鍵盤焦點；背景服務只向記錄的來源 App 讀取目標視窗。第一次 AX 讀取尚未完成時，面板立即接收按鍵，保存有界的命令佇列，明示正在取得視窗。取消或切換 App 時清空佇列，不能晚到才操作其他視窗。
- 使用同一個已擷取的 AX 視窗作為這次模式的目標；不能在每個按鍵重新使用「現在最前面的視窗」，因為現在可能是 Cue 自己。從主搜尋進入時沿用 launcher 已保存的來源 PID。
- 點到其他 App、⌘Tab 切換、睡眠、關閉模式或目標視窗失效時結束 session。外部焦點改變後不再搶回焦點；正常完成才返回原 App。不重送未知按鍵給原 App，避免在錯誤視窗插入內容。
- 進入功能設定時取消尚未開始的動作。關閉設定可回到同一模式，但必須重新驗證目標，不自動執行舊佇列。模式關閉時未綁定的輸入不得被攔截。

Cue 透過來源 App 的 AXFocusedWindow 取得目標，不以面板顯示後的新焦點重新猜測。若特定 App 無法提供可辨識的來源視窗，會明確顯示不支援。

## 功能設定與數字預設

設定入口留在視窗模式及 `Window Settings`／`視窗設定` 指令中，主 Settings 不新增一整頁布局表。

設定包含啟用開關、啟動快捷鍵、調整後保留面板、按鍵對照表，以及 1–9 的預設列表。每個預設可新增／編輯／刪除，顯示數字、名稱和矩形縮圖。編輯方式為「使用目前目標視窗的位置」或輸入相對 X、Y、寬、高的百分比，旁邊即時顯示純示意圖；按儲存才改資料，不移動真實視窗。

預設矩形以**目的顯示器可用範圍的比例**保存，例如左 2/3、中央 80% × 85%。數字預設套用於當前顯示器，不保存顯示器陣列索引或某台電腦的絕對座標，讓不同解析度、不同電腦可沿用。輸入限制為有限值、正尺寸且位於 0–100% 範圍；名稱及各設定提供英文／正體中文介面。自訂預設可先留空，由使用者加入，不擅自占用 1–4。

「儲存目前視窗」採用進設定前已驗證的目標幾何快照；目標若已失效就要求重新選定，不能把 Cue 設定視窗存成預設。不存視窗標題、文件內容或 App 的私人資料。

## 顯示器與幾何規則

1. **統一座標。** 幾何核心使用螢幕左上角為原點的桌面座標；AXPosition 也是左上角座標。從 AppKit 的座標轉換時以 primary screen 的高度翻轉 Y，不能用 Cue 面板所在的 `NSScreen.main`。所有尺寸使用 points，不混用 Retina pixels。[Apple AXPosition](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute)、[Apple NSScreen.screens](https://developer.apple.com/documentation/AppKit/NSScreen/screens?changes=_8&language=objc)
2. **可用範圍。** 每次 invocation／動作前取得最新的 `visibleFrame` 快照作為半屏、填滿、置中的邊界；跟隨選單列、Dock、顯示器排列變化。顯示器新增、拔除或旋轉時使舊快照失效，不能一直快取 `NSScreen.screens`。[Apple visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)、[Apple NSScreen.screens](https://developer.apple.com/documentation/AppKit/NSScreen/screens?changes=_8&language=objc)
3. **目前顯示器。** 視窗與哪個顯示器有最大交集就歸哪個；相同時以視窗中心及穩定識別碼決定。完全離屏時採最近顯示器，且只在使用者執行調整後收回可見區域。
4. **找方向。** 依系統顯示器的實際排列選下一個顯示器，先選指定半平面的候選，再偏好垂直於移動方向有重疊且方向距離近者，以邊界距離和穩定 ID 解決平手。沒有候選不循環跳回另一端。鏡像顯示器視為同一工作範圍；測試必須涵蓋不相接的顯示器、上下排列與負座標。
5. **跨顯示器移動。** 保持目前的 point 尺寸，只在目的範圍容不下時縮小；以來源可用範圍中的相對中心位置映射到目的範圍，最後限制在可見區域。不會意外放大視窗；數字預設矩形則依上節比例重新計算。
6. **精確與限制。** 以共同分界線計算左右／上下兩半，再對齊 point 邊界，避免奇數寬度產生縫隙。讀回實際結果並容許合理的 1–2 pt 誤差。App 可能強制最小尺寸或格線；不能假設所有視窗都能精確縮成半屏。

## 還原與例外

- 每次成功且實際改變幾何的命令記錄 before／after；以 process identity 與 AX element identity 區分視窗，不依視窗標題識別。Tab 只交換最近一組已確認狀態，不把 no-op、完全失敗或未確認的寫入算成歷史。部分成功且已讀回實際幾何的操作保留 before／實際 after，讓使用者仍可還原。
- 還原資料僅保留記憶體中，設定小型上限，最近 50 個視窗。App 結束、視窗銷毀或權限撤銷時釋放；不承諾跨重開機還原。還原前如果實際幾何已被使用者／其他工具更改，停用過期的切換記錄，避免回復到不相關位置。
- 原顯示器消失時，用保存的比例映射至目前目標顯示器並限制在可見範圍；畫面提示已調整還原位置。螢幕拓樸變更時取消待處理命令，重新取得目標；不重播舊操作。
- 對目標先確認 position／size 屬性是否可寫。固定尺寸視窗仍可置中或換顯示器；無法 resize 時不假裝半屏成功。對話框、sheet、最小化視窗、Cue 自己的視窗及不支援的 AX 元素給出具體提示，不主動解除最小化或移動 parent window。[Apple AXUIElement API](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- 位於 macOS 原生全螢幕狀態的目標，會提示先離開全螢幕；不以模擬綠色按鈕或未公開 Spaces API 偷渡。已送出的 AX 呼叫無法保證立即取消；取消後不送下一個 setter，也不把晚到結果套到新 session。
- 寫入位置和大小並非跨 App 原子交易。採有界的 resize／position 順序與讀回確認；部分成功則以真實幾何回報並保留可還原的 before，不無限重試、不默默移動另一扇視窗。若無法讀回，顯示「尚無法確認視窗狀態」，不要謊報成功。

## 實作邊界

- **CueCore 幾何／狀態邏輯：** 純值型別表達 screen snapshot、frame、command、preset、restore state。半屏、置中、顯示器選擇與座標轉換不依賴 AppKit／AX，能直接測試。
- **Window service：** 專用 actor／序列 worker 包住 AX capture、驗證、setter、讀回；參考 `SelectedTextService` 的可注入 driver 和 session cancellation，不把視窗功能塞入文字轉換服務。AX reference 不跨 actor 任意使用。
- **Window mode controller/view：** 主執行緒只做本地按鍵路由、輕量幾何顯示及狀態更新；原生 panel 重用，App icon 使用快取。啟動、一般搜尋、背景閒置均不列舉其他 App 的視窗。
- **熱鍵：** 延用 `HotKeyManager` 的 Carbon 全域啟動鍵；模式內由 key panel 接收本地按鍵，不設全域 event tap。manager 的 signature 共用，ID 由 App 層共用遞增序列分配，避免兩個 manager 互相觸發；按住不重複呼叫，喚醒後重設按住狀態。替換快捷鍵保留目前「先取得新鍵、成功後才釋放舊鍵」行為；驗證 ⌥M 與 launcher 自訂鍵及 Moom 的衝突。Moom 仍占用 ⌥M 時提示由使用者停用舊綁定或改鍵，不自動停止 Moom。
- **權限：** 共用 Cue 既有 Accessibility 信任狀態。只有使用者啟用／使用此功能時才顯示相關授權說明及系統入口；不在啟動 App 時彈窗、不自動修改權限。使用者已授權的安裝版本可能可沿用，仍以系統實際信任狀態為準。[Apple AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- **延遲上限：** 每個 AX element 設 messaging timeout，避免無回應的目標長時間占用 worker。目前每次 IPC 120 ms、整筆操作 900 ms 的內部預算；這是失敗上限，不是人工等待。鍵盤事件不可同步等待 AX。除了動作進行中，不設輪詢或常駐掃描。[Apple AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)

Cue 使用系統全域啟動鍵與面板內的本地按鍵，不設全域 event tap。安全輸入（例如未解鎖密碼管理器）可能使 Option+字母交給原 App，輸出鍵盤配置對應字元；遇到此情況可在視窗設定改用不同組合，或從選單列開啟。Cue 不會繞過 macOS 安全輸入。

## 支援範圍

此模式處理目前單一視窗，不提供滑鼠拖曳吸附、綠色按鈕選單、整個桌面／多 App
布局、每 App 規則、跨 Spaces 搬移或定時還原。原生全螢幕視窗需先離開全螢幕。
App 的最小尺寸、格線或 AX 支援程度可能限制調整結果；Cue 讀回實際幾何並顯示
限制，不把未確認的寫入當作成功。

## 可重現的隔離檢查

- `WindowGeometryTests`：比例、半屏、負座標、方向、可用範圍與多顯示器幾何。
- `scripts/check-window-service.sh`：注入 AX driver，檢查序列操作、取消、部分成功、讀回、權限、50 筆歷史上限與還原。
- `scripts/check-window-settings.sh`：暫存設定檔、衝突回復、快速儲存、版本／大小／權限錯誤、英文與正體中文離屏介面。
- `scripts/check-window-mode.sh`：晚到回覆、佇列取消、按鍵／修飾鍵與離屏面板。

以上不呼叫真實視窗控制，不讀使用者資料，也不啟動實際網路。真實全域快捷鍵、來源視窗辨識、多螢幕及不同 App 相容性不能由這些測試取代。

全新安裝與更新後的權限引導使用注入狀態涵蓋未授權、有效授權、過期／撤銷、
回到系統設定、快捷鍵衝突、保留關閉選擇，以及不重播授權前的操作。設定備份
檢查確認匯入不覆蓋目的 Mac 的啟用選擇。多顯示器、不同 App 與實際快捷鍵的
相容性仍需在對應機器驗證；不能用幾何或離屏測試宣稱全部實機情境均受支持。
