# Emoji search / Emoji 搜尋

## English

Search a bundled emoji catalog using English or
Traditional Chinese names and keywords, then copy the result from the keyboard.

### Find and copy an emoji

1. Invoke Cue with **Option+Space**, type **`emoji`** or **`表情符號`**, and open
   **Emoji Search**.
2. Type a name or keyword in English or Traditional Chinese.
3. Move with **Up/Down** and press **Return**, double-click a result, choose
   **Copy**, or press its **Command+1–9** shortcut. Cue copies the emoji and closes.
4. Press **Command+V** in the destination app to paste it.

An empty Emoji search field shows a fixed starter set. The page shows at most
nine matching results without a scrollbar. A single click only selects a row. Refine your
query to find another result. **Esc** returns to the main launcher. This first
version has no extra settings and does not paste into another app automatically.
Emoji searches stay in this page; a query without matches does not become a
Google search.

### Catalog and privacy

The catalog contains 3,655 fully qualified emoji sequences from Unicode Emoji
15.0, with English and Traditional Chinese names/keywords based on CLDR 42.
Skin-tone variants are included and can be found using keywords; there is no
separate skin-tone picker. Emoji added after Unicode Emoji 15.0 are not included.

The emoji catalog and bilingual names/keywords ship with Cue. Both languages
can be searched regardless of the interface language. Search works offline from
first use, even with both Cue networking and browser search disabled. There is
no remote catalog lookup or download. Appearance depends on the emoji font
available in macOS and in the destination app. See [catalog data and provenance](emoji-data.md).

Emoji queries and result selections are not written to Cue's search-learning
history. Opening the feature through the main launcher's `emoji` command can
count as ordinary command use. Copying an emoji does not require Clipboard
History to be enabled; if recording is enabled, it follows the normal recording
rules. macOS Universal Clipboard and other clipboard managers retain their own
settings. See the [clipboard guide](clipboard.md) and [network policy](network-policy.md).

## 正體中文

用英文或正體中文名稱、關鍵字搜尋內附的 emoji 目錄，
再直接以鍵盤拷貝結果。

### 尋找與拷貝 emoji

1. 按 **Option+Space** 叫出 Cue，輸入 **`emoji`** 或 **`表情符號`**，開啟
   **表情符號搜尋**。
2. 輸入英文或正體中文名稱、關鍵字。
3. 用**上下方向鍵**選取並按 **Return**、按兩下結果、按**拷貝**，或按對應的 **Command+1–9**。
   Cue 會拷貝 emoji 並收起視窗。
4. 到需要的位置按 **Command+V** 貼上。

Emoji 搜尋欄空白時顯示一組固定的起始項目。頁面最多顯示九個符合結果、
不顯示捲軸；按一下只會選取項目，可縮小搜尋範圍來找其他結果。
**Esc** 返回主搜尋。此功能沒有額外設定，也不會自動貼入其他 App。
Emoji 搜尋只在此頁處理，找不到結果時不會轉成 Google 搜尋。

### 目錄與隱私

目錄包含 Unicode Emoji 15.0 的 3,655 組完整 emoji 序列，英文與正體中文名稱、
關鍵字以 CLDR 42 為基礎。支援膚色變體，可用關鍵字尋找，但沒有獨立的膚色
選擇器。不包含 Unicode Emoji 15.0 之後新增的 emoji。

Emoji 目錄及雙語名稱、關鍵字隨 Cue 內附，不論介面語言為何，都可以用兩種
語言搜尋。首次使用也完全離線，即使 Cue 自行連網與瀏覽器搜尋都關閉仍可
使用，不會連線查詢或下載目錄。實際外觀依 macOS 及目標 App 的 emoji 字型
而定。詳見[目錄資料與來源](emoji-data.md)。

Emoji 搜尋文字與選取結果不會寫入 Cue 的搜尋學習記錄；從主搜尋開啟 `emoji`
指令仍可視為一般指令使用。拷貝 emoji 不需開啟剪貼簿記錄；若記錄已開啟，
就依一般規則處理。macOS 通用剪貼簿與其他剪貼簿管理程式仍依各自設定運作。
詳見[剪貼簿說明](clipboard.md)與[網路政策](network-policy.md)。
