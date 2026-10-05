# System commands / 系統指令

Cue searches Sleep, Lock Screen, and Screen Off in English and Traditional Chinese. All use
the same Return / Command+number path as other results. The launcher dismisses
synchronously before invoking the action. A failure restores the query and shows
a localized error, unless a newer invocation has already replaced that request.
Successful requests participate in local search ranking; failed requests do not.

| Command | Search examples | Effect |
| --- | --- | --- |
| Sleep | `sleep`, `睡眠` | Requests system sleep. |
| Lock Screen | `lock`, `鎖定` | Requests a locked session. |
| Screen Off | `screen off`, `display off`, `關閉螢幕` | Requests immediate display sleep while leaving the Mac running. |

Screen Off runs `/usr/bin/pmset displaysleepnow`, the one-shot action documented
by macOS's installed `man pmset` manual. Process launch and waiting both happen on
a worker task, only after the user executes the command. The executable and its
single argument are fixed; no shell, administrator privileges, Accessibility
access, or power-setting changes are involved. A failed launch or nonzero exit
produces an error. Exit zero acknowledges the OS request; Cue does not poll the
display hardware to confirm its state.

Screen Off does not explicitly lock the session or put the whole Mac to sleep.
macOS's existing password-after-display-off policy still applies, and normal
keyboard or pointing-device input can wake the display. Power assertions or a
new input event may prevent it from remaining off. A screen saver is not used
as a silent fallback because it would leave the display on.

Sleep uses `IOPMFindPowerManagement` and `IOPMSleepSystem` on a worker task. The
connection is always closed and the return code is checked. macOS permits the
console user to make this request; Cue does not ask for administrator privileges.

Lock Screen dynamically resolves `SACLockScreenImmediate` in Apple's
`login.framework`, then calls it on the main actor. This is a private macOS entry
point, as also used in [Hammerspoon's implementation](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/caffeinate/libcaffeinate.m),
and must be rechecked when supporting new macOS releases. Loading happens only
after execution, off the input path. A missing framework or symbol produces an
error instead of crashing. Its void return does not acknowledge lock completion.
Never replace this with display sleep or change password requirements: turning
off a display does not guarantee a locked session. Lock Screen does not use
AppleScript, Accessibility access, keyboard-event synthesis, or an external executable.

`scripts/check-system-actions.sh` checks native command routing with an injected
action and a private, empty clipboard fixture. It also injects a process runner
to verify Screen Off's exact executable/argument, worker execution, launch errors,
and exit-status handling without launching `pmset`. It may load the lock service
to check symbol availability, but never invokes sleep, lock, or display sleep.
Actual system transitions require a deliberate manual check when the operator
is ready to resume or unlock the Mac.

Cue 支援以英文或正體中文搜尋睡眠、鎖定螢幕與關閉螢幕，使用 Return 或 Command+數字執行。
視窗會先立即關閉；若請求失敗且使用者尚未重新叫出 Cue，會恢復查詢並顯示錯誤。
成功的請求會納入本機搜尋排序；失敗的請求不會計入。

| 指令 | 搜尋範例 | 效果 |
| --- | --- | --- |
| 睡眠 | `sleep`、`睡眠` | 要求整台 Mac 進入睡眠。 |
| 鎖定螢幕 | `lock`、`鎖定` | 要求鎖定使用者工作階段。 |
| 關閉螢幕 | `screen off`、`display off`、`關閉螢幕` | 要求顯示器立即睡眠，Mac 繼續運作。 |

關閉螢幕使用 macOS 隨附 `man pmset` 手冊記載的一次性指令
`/usr/bin/pmset displaysleepnow`。只有執行指令後，才會在背景工作中啟動及等待程序；
執行檔與唯一參數均固定，不使用 shell、不要求管理員或輔助使用權限，也不修改電源設定。
啟動失敗或結束狀態非零時會顯示錯誤。結束狀態為零代表系統已接受請求；Cue 不會持續
查詢顯示器硬體狀態來確認是否已關閉。

關閉螢幕不會主動鎖定工作階段，也不會讓整台 Mac 進入睡眠。macOS 原有的螢幕關閉後
密碼要求仍會生效，一般鍵盤或滑鼠操作可以喚醒顯示器。防止睡眠的系統請求或新的輸入
可能讓螢幕無法維持關閉。螢幕保護程式仍會亮著螢幕，因此失敗時不會悄悄改用螢幕保護程式。

睡眠使用公開的 `IOPMFindPowerManagement` 與 `IOPMSleepSystem` 電源管理 API，
在背景執行、檢查回傳碼並關閉連線，不要求管理員權限。鎖定螢幕則在執行時才於背景
動態載入 `login.framework` 的 `SACLockScreenImmediate`，接著在主執行緒呼叫它。
這是 macOS 私有服務，支援新版 macOS 時必須再次確認相容性。找不到服務會顯示錯誤，
其無回傳值的介面無法確認鎖定完成。鎖定不使用 AppleScript、輔助使用權限、模擬按鍵
或外部執行檔，也不更改密碼要求；不能將關閉顯示器當成鎖定成功。

`scripts/check-system-actions.sh` 以注入的動作與獨立空白剪貼簿檢查原生操作路徑，
並注入程序執行器，確認關閉螢幕的固定執行檔與參數、背景執行、啟動錯誤及結束狀態處理。
測試可能載入鎖定服務確認符號存在，但不會啟動 `pmset`，也不會實際睡眠、鎖定或關閉
測試者的螢幕。真實的狀態切換需要等操作者準備好喚醒或解鎖 Mac 時，再手動驗證。
