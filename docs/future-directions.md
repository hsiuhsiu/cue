# Future directions / 未來方向

These ideas were recorded on 2026-09-27. Except for Chinese conversion, released
in Cue 0.5.0, they remain future directions, not an implementation plan or a
commitment to a release order. Build them one at a time when requested; do not
add dependencies or generic plugin infrastructure just to anticipate them.

Chinese conversion was subsequently requested and included in Cue 0.5.0;
see [its guide](chinese-conversion.md). The other ideas remain deferred.

簡繁互轉已依後續要求加入 Cue 0.5.0，見[功能說明](chinese-conversion.md)。其他項目
仍是預先記錄的方向，尚未實作，也不代表已排定版本或優先順序。之後依需求
逐項規劃，維持 Cue 最核心的快速、簡潔、輕量原則。

| Direction / 方向 | Intended behavior / 預期用途 |
| --- | --- |
| Chinese text conversion / 簡繁互轉 | Convert selected text directly, accounting for Taiwan and mainland China vocabulary as well as character forms. 直接轉換選取文字，並考慮台灣與中國大陸地區用詞，不只轉換字形。 |
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
- Prefer local work where practical. Define selection replacement, clipboard
  changes, exchange-rate fetching, API credentials, and what text leaves the Mac
  when each feature is actually designed. The GPT idea does not authorize sending
  text or making API calls now, or automatically on every search keystroke.
- Reuse concrete patterns as they emerge. Keep the existing launcher small rather
  than creating a plugin system before there is an actual need.

- 輸入、選取與叫出視窗必須保持即時；功能資料按需載入，耗時計算與必要連線
  放在背景，需要等待時明確顯示進度。
- 個別功能的設定留在該功能內，整體設定只放共用選項。
- 能在本機處理的工作優先在本機處理。取代選取文字、修改剪貼簿、取得匯率、
  API 金鑰與送出哪些文字，等實際規劃該功能時再明確決定；目前不進行 API
  呼叫，也不讓每次搜尋輸入自動送出文字。
- 有具體重複需求時才整理共用程式，不預先建立大型外掛架構。
