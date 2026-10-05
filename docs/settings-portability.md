# Settings backup & transfer / 設定備份與移轉

Open **Cue Settings → Backup & Transfer** using ⌘,.

按 ⌘, 開啟 **Cue 設定 → 備份與移轉**。

## Export / 匯出

Choose **Export Settings…** to save a portable settings file. Ordinary backups are readable JSON and exclude API keys. Optionally turn on **Protect with a password**; use at least 12 characters and enter the password twice. To carry an OpenAI API key, also explicitly select **Include my OpenAI API key**. This requires encryption, and macOS may ask for Keychain access. Cue never saves the backup password and cannot recover it if forgotten.

選擇「匯出設定…」儲存可攜的設定檔。一般備份是可閱讀的 JSON，不含 API key。也可以開啟「使用密碼保護」，輸入至少 12 個字元的密碼並再次確認。若要攜帶 OpenAI API key，必須另外勾選包含金鑰，且使用密碼加密；macOS 可能要求鑰匙圈存取授權。Cue 不儲存備份密碼，忘記後無法復原。

## Import / 匯入

Choose **Import Settings…**, select a backup, and enter its password if encrypted. Review the current and incoming values, then select the sections to apply. Unlisted app aliases, browsers and numbered window presets are kept; matching bundle identifiers or preset numbers receive the imported values. A shortcut or alias conflict prevents the import from changing settings. Directly swapping two already-registered global shortcuts requires first assigning one an unused shortcut.

選擇「匯入設定…」並選取備份；加密檔需先輸入密碼。確認本機與備份的值，再選擇要套用的區塊。備份未列出的 App 別名、瀏覽器與數字視窗配置會保留；相同 bundle ID 或配置編號則套用備份的值。若快捷鍵或別名衝突，匯入會停止並保留原設定。若要對調兩個正在使用的全域快捷鍵，請先把其中一個改成尚未使用的組合。

Clipboard retention and API key restoration are **off by default** in the import preview. Retention needs a separate confirmation because shortening it can permanently remove older local history. Restoring a key replaces Cue’s existing OpenAI key in macOS Keychain; a backup without a key never deletes the existing one. Settings, key restoration and clipboard cleanup report their outcomes separately. Importing a language change requires reopening Cue.

匯入預覽中的「剪貼簿保留時間」與「還原 API key」預設不勾選。縮短保留時間可能永久刪除本機較舊的記錄，因此需要另外確認。還原金鑰會替換 macOS 鑰匙圈內 Cue 原有的 OpenAI key；不含金鑰的備份不會刪除原 key。設定、金鑰還原與剪貼簿清理會分別回報結果。更換介面語言後需重新開啟 Cue。

## Included and excluded / 包含與排除

| Data / 資料 | Behavior / 處理方式 |
| --- | --- |
| Language, launcher shortcut, display and focus behavior / 語言、主視窗快捷鍵、顯示與焦點行為 | Portable / 可攜帶 |
| App aliases and Chinese conversion aliases / App 別名與繁簡轉換別名 | App bundle IDs only; path-only aliases stay local / App 使用 bundle ID；僅綁定本機路徑的別名不匯出 |
| Explicitly chosen Google Search browsers / 明確加入的 Google 搜尋瀏覽器 | Bundle IDs, names and order; missing apps are reported / 保留 bundle ID、名稱與順序，提示尚未安裝的 App |
| GPT model and translation direction / GPT 模型與翻譯方向 | Portable; no request is sent / 可攜帶，不發送測試請求 |
| Clipboard retention / 剪貼簿保留期限 | Separate import consent / 匯入需另外確認 |
| Window shortcuts, panel behavior and presets 1–9 / 視窗快捷鍵、面板行為與 1–9 配置 | Relative geometry; no screen IDs or window contents / 相對位置與大小，不含螢幕 ID 或視窗內容 |
| API key / API 金鑰 | Only explicitly selected encrypted backups / 僅限明確選擇的加密備份 |
| Network, browser-search enablement, recording, window enablement, updates, login and permissions / 連網、瀏覽器搜尋開關、剪貼簿記錄、視窗啟用、更新、登入及權限 | Preserve the destination Mac’s choices / 保留目的 Mac 的選擇 |
| Clipboard text, conversations, search learning, caches and local paths / 剪貼簿內容、對話、搜尋習慣、快取及本機路徑 | Excluded / 排除 |

Backup and restore are local, explicit actions. Neither operation enables network access, launches browsers or sends API requests. Settings files can still reveal custom names and preferences; choose a suitable storage location even when no key is included.

備份與還原都是明確觸發的本機操作，不會開啟網路、瀏覽器或發送 API 請求。即使不含金鑰，設定檔仍可能透露自訂名稱與偏好，請選擇適當的儲存位置。

## Format and implementation

- Versioned allowlist schema (`cue-settings`, schema version 1); 1 MiB file limit, nesting and item limits. Unknown schema versions, duplicate JSON keys, invalid values and conflicting settings are rejected; unsupported fields are ignored with a notice.
- Encrypted envelopes use **AES-256-GCM**, a fresh random 16-byte salt and 12-byte nonce, and authenticated version/algorithm/KDF metadata. Passwords use NFC-normalized UTF-8 with no whitespace trimming, **PBKDF2-HMAC-SHA256, 600,000 iterations**, and a 32-byte derived key. Import accepts bounded costs of 600,000–1,200,000 iterations. The password limit is 1,024 UTF-8 bytes.
- The entire payload is encrypted, including an optional key. There are no plaintext secret temporary files, saved passwords or credential logs. Export writes a private 0600 temporary file and atomically replaces the chosen destination.
- File I/O, password derivation and cryptography run off the main thread. Import validates the complete candidate before mutation, reserves both global shortcuts before changing either, and attempts rollback on persistence failure. Credential restoration and irreversible retention cleanup are separate final steps, with explicit outcomes.
- API keys remain in Cue’s existing non-synchronizing, device-local Keychain item. Swift strings and copy-on-write buffers cannot promise immediate erasure of every sensitive memory copy; backups are password-protected at rest, not protection from a compromised running Mac.

The cryptographic primitives use Apple’s [AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm) and [CommonCrypto password derivation](https://github.com/apple-oss-distributions/CommonCrypto/blob/main/include/CommonKeyDerivation.h). The initial PBKDF2 cost follows the [OWASP PBKDF2 guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#pbkdf2). Keychain storage retains [`kSecAttrSynchronizable = false`](https://developer.apple.com/documentation/security/ksecattrsynchronizable).

## Verification

Tests use synthetic settings, isolated preferences, temporary directories and fake key stores. They cover portable merges, excluded local flags, conflict and persistence failures, cancellation, key failure, wrong passwords, tampered ciphertext/headers, parameter bounds and Unicode normalization. PBKDF2 is also checked against published [RFC 7914 §11 vectors](https://www.rfc-editor.org/rfc/rfc7914.html#section-11). No real user credentials, clipboard histories or accounts are used as fixtures.
