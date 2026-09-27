# System commands / 系統指令

Sleep and Lock Screen are included in [Cue 0.3.0](https://github.com/hsiuhsiu/cue/releases/tag/v0.3.0).
睡眠與鎖定螢幕指令已包含在 Cue 0.3.0。

Cue searches Sleep and Lock Screen in English and Traditional Chinese. Both use
the same Return / Command+number path as other results. The launcher dismisses
synchronously before invoking the action. A failure restores the query and shows
a localized error, unless a newer invocation has already replaced that request.

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
off a display does not guarantee a locked session. No AppleScript, Accessibility
access, keyboard-event synthesis, or external executable is involved.

`scripts/check-system-actions.sh` checks native command routing with an injected
action and a private, empty clipboard fixture. It may load the lock service to
check symbol availability, but never invokes sleep or lock. Actual system
transitions require a deliberate manual check when the operator is ready to
resume or unlock the Mac.

Cue 支援以英文或正體中文搜尋睡眠與鎖定螢幕，使用 Return 或 Command+數字執行。
視窗會先立即關閉；若請求失敗且使用者尚未重新叫出 Cue，會恢復查詢並顯示錯誤。
睡眠使用公開的系統電源管理 API；鎖定使用動態載入的 macOS 私有服務，因此支援
新版 macOS 時必須再次確認相容性，不能將關閉顯示器當成鎖定成功。
自動測試只驗證執行路徑與服務是否可載入，不會實際睡眠或鎖定測試者的電腦。
