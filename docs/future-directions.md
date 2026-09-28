# Future directions / 未來方向

These ideas were recorded on 2026-09-27. Completed work is listed separately
below. The remaining ideas are future directions, not a commitment to a release
order. Build them one at a time when requested; do not add dependencies or generic
plugin infrastructure just to anticipate them.

以下區分已完成與尚未實作的方向。未完成項目不代表已排定版本或優先順序；
之後依需求逐項規劃，維持 Cue 最核心的快速、簡潔、輕量原則。

## Completed in 0.5.0 / 已於 0.5.0 完成

- **Chinese text conversion:** replace selected editable text in either direction,
  including Taiwan/mainland vocabulary. Runs fully offline with bundled
  dictionaries; `st` / `ts` aliases are customizable in the feature's own settings.
  See the [conversion guide](chinese-conversion.md) for permissions and limits.
- **簡繁互轉：**直接取代選取的可編輯文字，支援兩個方向及台灣／中國大陸地區
  用詞。使用內附詞庫完全離線處理，可在功能設定自訂 `st`／`ts` 別名。
  權限與適用限制見[轉換說明](chinese-conversion.md)。

## Remaining ideas / 尚未實作

| Direction / 方向 | Intended behavior / 預期用途 |
| --- | --- |
| Link cleaner / 連結清理 | Remove known tracking parameters from a link in the clipboard while preserving its destination and functional parameters. 清除剪貼簿連結的追蹤參數，保留目的頁面及必要參數。 |
| Emoji finder / Emoji 搜尋 | Find and insert or copy emoji quickly from the keyboard. 用鍵盤快速搜尋並插入或拷貝 emoji。 |
| Calculator / 計算機 | Calculate expressions directly in Cue. 直接在 Cue 計算算式。 |
| Unit and currency conversion / 單位與幣值換算 | Convert units and currencies; decide exchange-rate sourcing and freshness when this feature is planned. 換算單位與幣值，匯率來源及更新方式留待該功能規劃時決定。 |
| GPT API answers / GPT API 回答 | Explicitly invoke a quick translation or general question mode. 明確選擇翻譯或一般提問，取得簡短回答。 |

## Design constraints / 設計原則

- Keep typing, selection, and invocation synchronous and light. Load feature data
  on demand; expensive work and any requested network calls stay off the input
  path, with clear progress when needed.
- Keep feature settings with the feature. Reserve Cue-wide Settings for shared
  controls; do not add every future option there.
- Every network feature must honor the global network setting, including retries
  and background work. When access is off, use available local functionality or
  clearly disable the feature; never silently fall back to a cloud service. See
  the [network policy](network-policy.md).
- Prefer local work where practical. Define selection replacement, clipboard
  changes, exchange-rate fetching, API credentials, and what text leaves the Mac
  when each feature is actually designed. The GPT idea does not authorize sending
  text or making API calls now, or automatically on every search keystroke.
- Reuse concrete patterns as they emerge. Keep the existing launcher small rather
  than creating a plugin system before there is an actual need.

- 輸入、選取與叫出視窗必須保持即時；功能資料按需載入，耗時計算與必要連線
  放在背景，需要等待時明確顯示進度。
- 個別功能的設定留在該功能內，整體設定只放共用選項。
- 所有連網功能都必須遵守全域網路開關，包含重試及背景工作；關閉時使用可用的
  本機功能，或明確停用，不可悄悄改用雲端服務。詳見[網路政策](network-policy.md)。
- 能在本機處理的工作優先在本機處理。取代選取文字、修改剪貼簿、取得匯率、
  API 金鑰與送出哪些文字，等實際規劃該功能時再明確決定；目前不進行 API
  呼叫，也不讓每次搜尋輸入自動送出文字。
- 有具體重複需求時才整理共用程式，不預先建立大型外掛架構。
