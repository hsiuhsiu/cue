# 安裝 Cue

Cue 是選單列中的 macOS 應用程式啟動器。按下 **Option+Space** 即可搜尋並開啟 App；安裝不需要 Xcode 或終端機。

## 下載

- [下載 Cue 0.1.0 通用版 DMG](https://github.com/hsiuhsiu/cue/releases/download/v0.1.0/Cue-0.1.0-universal.dmg)
- [版本說明與下載檔案](https://github.com/hsiuhsiu/cue/releases/tag/v0.1.0)

目前儲存庫是私有的，請先登入有權存取 `hsiuhsiu/cue` 的 GitHub 帳號。沒有權限時，連結可能顯示找不到頁面。

安裝檔同時包含 Apple silicon 與 Intel 版本，最低建置目標為 macOS 14。這次預覽版僅在 **Apple silicon、macOS 26.6.2** 實際執行測試；Intel 與其他 macOS 版本尚未驗證。

## 安裝與更新

1. 若 Cue 正在執行，先從選單列的 Cue 圖示選擇 **Quit Cue**。
2. 開啟下載的 **Cue-0.1.0-universal.dmg**。
3. 將 **Cue.app** 拖曳至 **Applications／應用程式**。若已有舊版本，選擇取代。
4. 從「應用程式」開啟 Cue，再退出掛載的 Cue 磁碟映像。

Cue 會出現在選單列，不會顯示 Dock 圖示。按下 **Option+Space**，或從選單列選擇 **Show Cue** 即可開啟搜尋面板。

## 首次開啟

此預覽版只有 ad-hoc 簽章，尚未使用 Developer ID 簽署，也未經 Apple 公證。首次開啟時，macOS 可能顯示無法驗證開發者或無法檢查 App 的提示。

確認檔案來自上方的 Cue 版本頁面，且你信任這個版本後，可依 Apple 官方流程操作：

1. 先在「應用程式」中嘗試開啟 Cue。
2. 開啟「系統設定」中的「隱私權與安全性」，向下找到 Cue 的提示，按「強制打開」。
3. 再次出現提示時，確認要執行 Cue，再按「打開」。

以上流程依據 [Apple：在 Mac 上安全地開啟 App](https://support.apple.com/zh-tw/102445)。公司管理的 Mac 可能限制相關選項。若沒有「強制打開」或仍無法開啟，請回報提示內容；此預覽版尚未驗證其他機器的首次安裝。若提示指出 App 已損壞或會損壞電腦，請停止安裝並回報。

## 開始使用

| 操作 | 功能 |
| --- | --- |
| Option+Space | 顯示或關閉 Cue，這是預設快捷鍵 |
| 直接輸入 App 名稱 | 搜尋應用程式 |
| 上／下方向鍵、Enter | 選擇並開啟搜尋結果 |
| Escape | 關閉搜尋面板 |
| Cue 中按 Command+, | 開啟設定 |

設定頁可以更改全域快捷鍵、搜尋結果數量、顯示螢幕，以及切換 App 時是否關閉面板。設定會立即保存。若預設快捷鍵被其他 App 使用，請從 Cue 選單列的 **Settings…** 更換。

安裝或移除其他 App 後，在 Cue 輸入 **更新索引**、`reindex` 或 `refresh apps`，選擇 **Update App Index** 並按 Enter，即可重新掃描。

## 更新、重新安裝與限制

更新或重新安裝時，依照上方步驟退出 Cue、取代「應用程式」中的 Cue.app，再重新開啟。設定存放在 App 外，單純取代 Cue.app 會保留既有快捷鍵與其他設定。macOS 在更新後可能再次要求允許開啟，請參照[首次開啟](#首次開啟)流程。

這個版本尚未提供自動更新或登入時自動啟動功能。重新登入 Mac 後，請從「應用程式」開啟 Cue。應用程式索引會在 Cue 啟動時建立，也可以手動更新。

版本頁同時提供 **SHA256SUMS.txt**，供需要核對下載檔案完整性的人使用；檢查碼不代表 Apple 簽署或公證。
