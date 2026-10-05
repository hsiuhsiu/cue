# Link cleaner / 連結清理

## English

### Use it

1. Copy one HTTP or HTTPS link.
2. Invoke Cue with Option+Space and type **`clean link`**, **`link cleaner`**,
   **`清理連結`**, or **`清理網址`**.
3. Execute the selected command with **Return**, a click, or its displayed
   **Command+number**. Cue writes a cleaned link back to the clipboard when it
   finds recognized tracking parameters to remove.
4. Read the result in Cue, press **Esc** to close the launcher, then paste
   wherever you want with **Command+V**.

Cue reports progress, the number of removed parameters, that no parameters can
be safely removed, or a protected signed link. Invalid clipboard content produces an explanation
without replacing it. This command has no feature settings.

### What changes

The cleaner removes query parameter names matching `utm_*` with a nonempty
suffix, or exactly `fbclid`, `gclid`, `dclid`, `msclkid`, `twclid`, `ttclid`,
`mc_cid`, and `mc_eid`. Matching is case-insensitive and decodes a parameter name
once. It preserves the destination, other query parameters and their order,
duplicate retained parameters, fragments, and their original encoding rather
than rebuilding the whole URL. General names such as `ref`, `source`, `si`,
`igsh`, and `igshid` are retained.

Query fields are separated at `&`. A field containing a literal `;` is retained
because servers differ on whether that character separates parameters or belongs
to a value. Other ordinary fields can still be cleaned. A recognized signature
name in any semicolon-separated part protects the entire URL instead.

If the query contains `x-amz-signature`, `x-goog-signature`, `signature`, `sig`,
`oauth_signature`, or `hmac`, the whole URL is protected from modification.
Changing part of a signed link can invalidate it. These markers are a
conservative safeguard, not a complete detector for every site's signing scheme.

The input must be a single absolute HTTP or HTTPS URL with a host and at most
64 KiB of UTF-8 text. Surrounding whitespace is ignored for parsing. Raw
whitespace inside the URL, control characters, backslashes, malformed percent
escapes, and other protocols are rejected.

This is local parameter removal, not a guarantee that a site cannot track a
visit. Unknown tracking formats can remain. Short links and redirect URLs are
not expanded, and the destination is not fetched or tested.

### Clipboard and privacy

The command works without enabling Clipboard History and does not read or clean
clipboard content while you merely type a command. It acts only after you
execute it. Processing runs away from the typing path, and a detected clipboard
change while the command is pending prevents overwriting the newer copy.
If the link is unchanged, Cue leaves the clipboard as it was.

For a changed link, Cue writes plain text and URL clipboard formats rather than
keeping rich text that still points to the old URL. It accepts one clipboard
item; preserving a rollback copy is limited to 32 formats and 16 MiB in total.
Content exceeding those limits is left untouched.

Cue does not open a browser, paste into another application, or save the URL in
its search-learning history. If Clipboard History recording is enabled, the
cleaned copy follows its normal recording rules; concealed/transient clipboard
markers are preserved so those copies remain excluded. Cleaning is entirely local and works with Cue's
own network access and browser search both disabled. macOS clipboard services
and other clipboard managers follow their own settings; see the
[network policy](network-policy.md).

## 正體中文

### 使用方式

1. 複製一個 HTTP 或 HTTPS 連結。
2. 按 Option+Space 叫出 Cue，輸入 **`clean link`**、**`link cleaner`**、
   **`清理連結`**或 **`清理網址`**。
3. 按 **Return**、點選結果，或按畫面顯示的 **Command+數字**執行。若有可移除
   的已知追蹤參數，Cue 會將清理後的連結寫回剪貼簿。
4. 在 Cue 查看結果，按 **Esc** 收起主視窗，再到需要的位置按 **Command+V** 貼上。

Cue 會顯示處理進度、移除參數數量、沒有可安全移除的參數，或簽署網址受保護的結果。
若剪貼簿內容無效，會顯示原因而不取代內容。此功能沒有額外的功能設定。

### 會修改哪些內容

清理器會移除名稱為 `utm_*` 且後綴至少一個字元，或恰好為 `fbclid`、`gclid`、`dclid`、
`msclkid`、`twclid`、`ttclid`、`mc_cid`、`mc_eid` 的查詢參數。比對時不區分
大小寫，參數名稱只解碼一次。保留目的位置、其他參數與順序、重複的保留參數、
網址片段及原有編碼，不重新組合整個網址。`ref`、`source`、`si`、`igsh`、
`igshid` 等通用名稱會保留。

查詢欄位以 `&` 分隔。含未編碼分號 `;` 的欄位會保留，因為不同伺服器可能把它
當成參數分隔符，或參數值的一部分；其他一般欄位仍可清理。若分號分隔出的任一
部分含已知簽章名稱，則整個網址保持原樣。

若查詢參數含 `x-amz-signature`、`x-goog-signature`、`signature`、`sig`、
`oauth_signature` 或 `hmac`，整個網址會受保護而不修改，避免修改其中一部分
後使簽署失效。這些標記是保守防護，不是能辨識所有網站簽署方式的完整偵測。

輸入須是單一完整 HTTP 或 HTTPS 網址、含主機名稱，且 UTF-8 文字最多 64 KiB。
解析時忽略前後空白；網址內未編碼的空白、控制字元、反斜線、格式錯誤的百分比
編碼及其他通訊協定都不接受。

這是在本機移除參數，不代表網站無法追蹤造訪；未識別的追蹤格式仍可能保留。
不會展開短網址或重新導向連結，也不會連線取得或測試目的頁面。

### 剪貼簿與隱私

不需開啟剪貼簿歷史記錄就能使用此指令；單純打字時不會讀取或清理剪貼簿，
只有執行指令後才會處理。工作不阻塞打字流程；若等待期間偵測到剪貼簿已變更，
就不覆蓋較新的內容。若連結不需修改，剪貼簿會保持原樣。

需要清理時，Cue 寫入純文字與網址兩種剪貼簿格式，不保留仍指向舊網址的富文字。
只接受單一剪貼簿項目；為保留寫入失敗時的還原資料，原始格式最多 32 種、合計
16 MiB。超過限制的內容不會修改。

Cue 不會開啟瀏覽器、貼入其他 App，或將網址存進搜尋學習記錄。若已開啟剪貼簿
歷史記錄，清理後的拷貝依一般記錄規則處理；隱藏／暫存的剪貼簿標記會保留，
因此這類內容仍不會收錄。清理完全離線，
即使 Cue 自行連網與瀏覽器搜尋兩個開關都關閉，仍可使用。macOS 剪貼簿服務及
其他剪貼簿管理程式依各自設定運作；詳見[網路政策](network-policy.md)。
