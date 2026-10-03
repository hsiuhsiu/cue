# 視窗調整規劃

狀態：設計提案，尚未實作。目標是取代日常最常用的 Moom 鍵盤操作，保持 Cue 快速、簡潔、輕量。這份文件列出首版範圍與驗收條件；不代表已加入目前發行版。

## 建議方向

在 Cue 內加入獨立的「視窗調整模式」，預設用 **⌥M** 叫出。也能從 Cue 主搜尋輸入 `window`／`視窗` 進入同一模式。使用同一份 App、設定資料與權限，保持主搜尋的畫面及打字路徑不變。

這項功能採**自行啟用**：預設關閉，只有啟用後才註冊 ⌥M；關閉時立即釋放該快捷鍵、取消待處理動作。尚未啟用時，主搜尋入口顯示功能設定，讓使用者選擇啟用。既有 ⌥Space 與主搜尋不受影響。

專用模式適合這組固定、連續的鍵盤操作：不必每次先搜尋指令，也不會讓數字預設和主搜尋的 ⌘數字選取混在一起。所有操作離線完成；不需要 OpenAI、其他 API 或第三方套件。

## 首版操作

下列依使用習慣規劃；使用者已確認 Enter 填滿可用桌面、數字預設只控制目前單一視窗。模式退出策略仍是待實作驗證的建議。

| 輸入 | 行為 |
| --- | --- |
| ⌥M | 叫出／關閉視窗模式；設定中可更改啟動快捷鍵。 |
| ⌥←／→／↑／↓ | 目前顯示器的左／右／上／下半屏。每次都是明確的半屏，不加入連按四分之一屏等隱藏規則。 |
| ⌘←／→／↑／↓ | 移到該方向的另一個顯示器。沒有目的顯示器時不移動，顯示簡短提示。 |
| Return／Enter | **填滿可用桌面**：保留選單列與 Dock 所需空間，不進入 macOS 的獨立全螢幕 Space。已確認。 |
| Space | 在目前顯示器的可用範圍水平、垂直置中，保持大小；過大的視窗以可達標題列為優先。 |
| Tab | 回到這個視窗上一次由 Cue 操作前的大小、位置與顯示器；再次執行可在最近兩個狀態間切換。 |
| 1–9 | 套用使用者儲存的尺寸與位置，例如左 60%／右 40%。每個數字作用於**當前單一視窗**；未設定的數字不執行。已確認。 |
| Esc | 關閉模式、保留已完成的調整，不另外回復視窗。 |
| ⌘, | 開啟這項功能自己的設定。 |

Moom 官方也將 Fill Screen 與 macOS Full Screen 分開，且提供方向鍵、Return、Space、Tab 的自訂動作。這是上述 Enter 建議的依據；Cue 不必複製 Moom 的所有組合行為。[Moom Keyboard](https://manytricks.com/moom/help/keyboard.html)

## 模式與畫面

- 以小型原生浮動面板顯示目標 App、簡單的顯示器／視窗示意及按鍵提示。沿用 Cue 淡藍色重點色、留白與線條圖示，不加入搜尋框、全桌面遮罩或進出動畫。示意圖由幾何資料繪製，不擷取畫面。
- 動作直接執行，不再按一次 Enter 確認。建議半屏、置中、填滿、還原、數字預設成功後即關閉並返回原 App；**移動顯示器先保留模式**，方便接著按 ⌥方向調整。這項退出策略尚未定案。
- 多次命令以序列處理，後續幾何以已確認的實際結果為準。不用 debounce 等待使用者停止輸入。相同半屏等冪等動作的鍵盤自動重複可忽略；Tab、數字與啟動鍵的自動重複一律忽略，避免反覆切換。
- Cue 先記錄啟動前的來源 App，面板取得鍵盤焦點；背景服務只向記錄的來源 App 讀取目標視窗。第一次 AX 讀取尚未完成時，面板立即接收按鍵，保存有界的命令佇列，明示正在取得視窗。取消或切換 App 時清空佇列，不能晚到才操作其他視窗。
- 使用同一個已擷取的 AX 視窗作為這次模式的目標；不能在每個按鍵重新使用「現在最前面的視窗」，因為現在可能是 Cue 自己。從主搜尋進入時沿用 launcher 已保存的來源 PID。
- 點到其他 App、⌘Tab 切換、睡眠、關閉模式或目標視窗失效時結束 session。外部焦點改變後不再搶回焦點；正常完成才返回原 App。不重送未知按鍵給原 App，避免在錯誤視窗插入內容。
- 進入功能設定時取消尚未開始的動作。關閉設定可回到同一模式，但必須重新驗證目標，不自動執行舊佇列。模式關閉時未綁定的輸入不得被攔截。

這裡最需要原型驗證的是「Cue 已取得鍵盤焦點，仍能可靠辨識啟動前的來源視窗」。先沿用已解決 launcher 焦點問題的正常 key panel，透過來源 App 的 AXFocusedWindow 取目標；若特定 App 無法提供可辨識的來源視窗，明確顯示不支援，不能猜另一扇視窗。

## 功能設定與數字預設

設定入口留在視窗模式及 `Window Settings`／`視窗設定` 指令中，主 Settings 不新增一整頁布局表。

首版設定只包含啟用開關、啟動快捷鍵、按鍵對照表，以及 1–9 的預設列表。每個預設可新增／編輯／刪除，顯示數字、名稱和矩形縮圖。編輯方式為「使用目前目標視窗的位置」或輸入相對 X、Y、寬、高的百分比，旁邊即時顯示純示意圖；按儲存才改資料，不移動真實視窗。

預設矩形以**目的顯示器可用範圍的比例**保存，例如左 2/3、中央 80% × 85%。首版預設套用於當前顯示器，不保存顯示器陣列索引或某台電腦的絕對座標，讓不同解析度、不同電腦可沿用。輸入限制為有限值、正尺寸且位於 0–100% 範圍；名稱及各設定提供英文／正體中文介面。自訂預設可先留空，由使用者加入，不擅自占用 1–4。

「儲存目前視窗」採用進設定前已驗證的目標幾何快照；目標若已失效就要求重新選定，不能把 Cue 設定視窗存成預設。不存視窗標題、文件內容或 App 的私人資料。

## 顯示器與幾何規則

1. **統一座標。** 幾何核心使用螢幕左上角為原點的桌面座標；AXPosition 也是左上角座標。從 AppKit 的座標轉換時以 primary screen 的高度翻轉 Y，不能用 Cue 面板所在的 `NSScreen.main`。所有尺寸使用 points，不混用 Retina pixels。[Apple AXPosition](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute)、[Apple NSScreen.screens](https://developer.apple.com/documentation/AppKit/NSScreen/screens?changes=_8&language=objc)
2. **可用範圍。** 每次 invocation／動作前取得最新的 `visibleFrame` 快照作為半屏、填滿、置中的邊界；跟隨選單列、Dock、顯示器排列變化。顯示器新增、拔除或旋轉時使舊快照失效，不能一直快取 `NSScreen.screens`。[Apple visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)、[Apple NSScreen.screens](https://developer.apple.com/documentation/AppKit/NSScreen/screens?changes=_8&language=objc)
3. **目前顯示器。** 視窗與哪個顯示器有最大交集就歸哪個；相同時以視窗中心及穩定識別碼決定。完全離屏時採最近顯示器，且只在使用者執行調整後收回可見區域。
4. **找方向。** 依系統顯示器的實際排列選下一個顯示器，先選指定半平面的候選，再偏好垂直於移動方向有重疊且方向距離近者，以邊界距離和穩定 ID 解決平手。沒有候選不循環跳回另一端。鏡像顯示器視為同一工作範圍；測試必須涵蓋不相接的顯示器、上下排列與負座標。
5. **跨顯示器移動。** 建議保持目前的 point 尺寸，只在目的範圍容不下時縮小；以來源可用範圍中的相對中心位置映射到目的範圍，最後限制在可見區域。這較接近 Moom 鍵盤模式的預設，且不會意外放大視窗。預設矩形則依上節比例重新計算。[Moom Keyboard](https://manytricks.com/moom/help/keyboard.html)
6. **精確與限制。** 以共同分界線計算左右／上下兩半，再對齊 point 邊界，避免奇數寬度產生縫隙。讀回實際結果並容許合理的 1–2 pt 誤差。App 可能強制最小尺寸或格線；不能假設所有視窗都能精確縮成半屏。

## 還原與例外

- 每次成功且實際改變幾何的命令記錄 before／after；以 process identity 與 AX element identity 區分視窗，不依視窗標題識別。Tab 只交換最近一組已確認狀態，不把 no-op、完全失敗或未確認的寫入算成歷史。部分成功且已讀回實際幾何的操作保留 before／實際 after，讓使用者仍可還原。
- 還原資料僅保留記憶體中，設定小型上限，例如最近 50 個視窗。App 結束、視窗銷毀或權限撤銷時釋放；不承諾跨重開機還原。還原前如果實際幾何已被使用者／其他工具更改，停用過期的切換記錄，避免回復到不相關位置。
- 原顯示器消失時，用保存的比例映射至目前目標顯示器並限制在可見範圍；畫面提示已調整還原位置。所有待處理命令在螢幕拓樸變更後重新計算。
- 對目標先確認 position／size 屬性是否可寫。固定尺寸視窗仍可置中或換顯示器；無法 resize 時不假裝半屏成功。對話框、sheet、最小化視窗、Cue 自己的視窗及不支援的 AX 元素給出具體提示，首版不主動解除最小化或移動 parent window。[Apple AXUIElement API](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- 位於 macOS 原生全螢幕狀態的目標，首版提示先離開全螢幕；不以模擬綠色按鈕或未公開 Spaces API 偷渡。已送出的 AX 呼叫無法保證立即取消；取消後不送下一個 setter，也不把晚到結果套到新 session。
- 寫入位置和大小並非跨 App 原子交易。採有界的 resize／position 順序與讀回確認；部分成功則以真實幾何回報並保留可還原的 before，不無限重試、不默默移動另一扇視窗。若無法讀回，顯示「尚無法確認視窗狀態」，不要謊報成功。

## 實作邊界

- **CueCore 幾何／狀態邏輯：** 純值型別表達 screen snapshot、frame、command、preset、restore state。半屏、置中、顯示器選擇與座標轉換不依賴 AppKit／AX，能直接測試。
- **Window service：** 專用 actor／序列 worker 包住 AX capture、驗證、setter、讀回；參考 `SelectedTextService` 的可注入 driver 和 session cancellation，不把視窗功能塞入文字轉換服務。AX reference 不跨 actor 任意使用。
- **Window mode controller/view：** 主執行緒只做本地按鍵路由、輕量幾何顯示及狀態更新；原生 panel 重用，App icon 使用快取。啟動、一般搜尋、背景閒置均不列舉其他 App 的視窗。
- **熱鍵：** 延用 `HotKeyManager` 的 Carbon 全域啟動鍵；模式內由 key panel 接收本地按鍵，首版不設全域 event tap。現有 manager 的 signature 固定且每個 instance 的 ID 從 1 開始，加入第二個 hotkey 時必須改成 App 層唯一的 ID／各功能唯一 signature，並測試兩個 manager 不互相觸發。替換快捷鍵保留目前「先取得新鍵、成功後才釋放舊鍵」行為；驗證 ⌥M 與 launcher 自訂鍵及 Moom 的衝突。Moom 仍占用 ⌥M 時提示由使用者停用舊綁定或改鍵，不自動停止 Moom。
- **權限：** 共用 Cue 既有 Accessibility 信任狀態。只有使用者啟用／使用此功能時才顯示相關授權說明及系統入口；不在啟動 App 時彈窗、不自動修改權限。使用者已授權的安裝版本可能可沿用，仍以系統實際信任狀態為準。[Apple AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- **延遲上限：** 每個 AX element 設 messaging timeout，避免無回應的目標長時間占用 worker。初步以每次 IPC 約 100–200 ms 的可調內部預算加上整筆動作 deadline 進行量測，再按相容性校準；這是失敗上限，不是人工等待。鍵盤事件不可同步等待 AX。除了動作進行中，不設輪詢或常駐掃描。[Apple AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)

Event tap 能觀察／過濾系統輸入，但有額外權限與生命週期負擔；目前需求可先使用啟動 hotkey 加本地 key panel，沒有理由預先加入。[Apple CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))

## 分段實作與驗收

1. **先驗證焦點與最小垂直切片：** ⌥M → 擷取原視窗 → 左／右半屏 → Esc → 焦點回原 App。驗證第二個 global hotkey 不影響 ⌥Space，接著才擴充完整面板。
2. **完成基本操作：** 四向半屏、填滿、置中、跨顯示器、Tab 還原，處理失效視窗、最小尺寸、權限變更及超時。
3. **加入數字預設與功能設定：** 1–9、儲存目前位置、比例編輯、設定關閉後回原模式，英文／正體中文與鍵盤可及性。
4. **效能與相容性：** 在 Release 測 capture、UI acknowledgment、AX apply/readback 的 p50／p95／max；區分 Cue 的排程時間與目標 App 回應時間。不新增搜尋路徑的 AX、檔案存取或按鍵 debounce。確認快速連按、冷啟動及慢／無回應的目標仍能立即 Esc。

大部分驗收使用純幾何與注入 driver：不同 DPI／解析度、Dock 邊、負座標、旋轉、鏡像、拔除顯示器、最小尺寸、部分 setter 成功、逾時、取消、PID 重用、window close、焦點競態、還原失效、按鍵衝突及舊 callback。以禁止 activation 的離屏原生 view 檢查排版和按鍵路由；不碰真實使用者視窗、設定、剪貼簿或網路。

僅最後的全域熱鍵、跨 App 焦點、系統權限與多顯示器實際動作安排一次受控實機測試，先取得合適時段；測試自己的空白文件／測試視窗，不自動移動使用者正在工作的視窗。實機涵蓋 AppKit、Safari、Electron、Terminal／iTerm2 等不同視窗行為；無法當次驗證的組合明確列出。

## 首版之外

滑鼠拖曳吸附、綠色按鈕選單、整個桌面／多 App 布局、視窗自動排列、每 App 規則、跨 Spaces 搬移、啟動 App、定時自動還原及完整任意按鍵編輯器均不列入首版。先把上述日常鍵盤操作做好，再依實際缺口增加。

## 已確認範圍與待驗證建議

- 已確認：Enter 填滿目前顯示器的可用桌面，保留選單列與 Dock；不進入原生全螢幕 Space。
- 已確認：數字預設控制目前單一視窗的大小／位置，例如左 60% 與右 40%；不包含多 App 布局。
- 待實作驗證：一般動作後關閉、移動顯示器後保留模式。如實際需要連續多步，可在功能設定提供「動作後保留模式」，不增加每次操作的確認步驟。
