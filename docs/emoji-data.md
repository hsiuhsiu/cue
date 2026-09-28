# Offline emoji catalog

Cue bundles **3,655 fully-qualified Unicode Emoji 15.0 sequences**, with English and Traditional Chinese names and keywords. The catalog is 709,972 bytes of JSON, plus a license and notice. It includes skin tones, gender and family sequences, flags, and variation selectors. Emoji 15.1 and newer additions are deliberately excluded to stay within the app's macOS 14 minimum; actual appearance comes from the system emoji font, and some flags can vary by region. There are no downloaded images or bundled emoji fonts.

This file documents the data pipeline. See [Emoji Search](emoji.md) for using the feature.

## Sources and license

- [Unicode Emoji 15.0 emoji-test.txt](https://www.unicode.org/Public/emoji/15.0/emoji-test.txt), dated August 12, 2022. Only `fully-qualified` records are retained; `component`, `minimally-qualified`, and `unqualified` records are not separate results. Source order is the CLDR emoji order.
- [CLDR 42](https://cldr.unicode.org/downloads/cldr-42), which introduced names and keywords for Emoji 15.0. The `release-42` tag resolves to commit `f800890ea86482c2eb5f73224897f4a8bc0b653a`. Both `common/annotations` and `common/annotationsDerived` contribute `en.xml` and `zh_Hant.xml`; the derived files provide skin-tone and other composed sequences.
- [The license at that same CLDR commit](https://github.com/unicode-org/cldr/blob/f800890ea86482c2eb5f73224897f4a8bc0b653a/unicode-license.txt) is included verbatim as `Unicode-LICENSE.txt`. `Emoji-NOTICE.txt` describes the sources and Cue's changes. These files ship beside `EmojiCatalog.json` in the app bundle.

Source URLs and SHA-256 hashes are pinned in [`scripts/prepare-emoji-data.py`](../scripts/prepare-emoji-data.py). The script refuses missing, modified, or unexpected inputs; it never silently switches to a newer Unicode release. The JSON schema has `formatVersion: 1`, `unicodeVersion: "15.0"`, `cldrVersion: "42"`, and an `entries` array. Each entry contains `emoji`, `name`, `traditionalName`, and `keywords`.

CLDR 42 provides English names for all 3,655 entries and Traditional Chinese names for 3,654. Cue adds the missing black-bird label **黑鳥** and the keywords 鳥/黑色. A small, explicit alias list adds 開心/happy to four smiling faces, 慶祝/派對 to three celebration emoji, 台灣/臺灣/Taiwan to the Taiwan flag, and 愛心 to 23 colored or decorated heart sequences. All final entries have both language labels. These additions are Cue-maintained conveniences, not changes claimed to be official CLDR translations. Original names, emoji sequences, and official keywords are otherwise retained.

## Reproduce the resources

Ordinary builds use the checked-in files. They need no Python, Unicode checkout, network access, or extra runtime dependency for emoji search.

For maintainers regenerating the data with Python 3:

```sh
python3 scripts/prepare-emoji-data.py --download
```

`--download` explicitly permits fetching missing, pinned inputs into `.build/emoji-upstream`. Downloaded content must match its pinned hash before it is saved. To reproduce without any network access after those inputs have been obtained:

```sh
python3 scripts/prepare-emoji-data.py --source-dir .build/emoji-upstream
```

The default output directory is `Sources/Cue/Resources`; use `--output-dir` for a comparison directory. Identical inputs and script produce identical JSON, license, and notice bytes. Expected catalog SHA-256:

```text
f1925a41eb445b45be70823f8824a09278a639bd8b4e0fe19a4510ce6ca0252b
```

Updating the catalog is an intentional source change: review new glyph compatibility, source hashes, license terms, translation coverage, and tests together. Runtime code never fetches these source URLs.

## Search behavior and cost

`EmojiCatalog` is an immutable `Sendable` value. The UI loads and prepares it once away from the main thread. It precomputes normalized UTF-8 search fields; a search reads those fields without file access, decoding, networking, locale collation over the whole catalog, or per-entry substring allocation. It retains only the requested best results instead of sorting every match.

Emoji font loading, shaping, and bitmap drawing also run off the main thread through CoreText. At most one batch of nine glyphs is active; subsequent requests replace the pending targets with the latest results. A bounded cache retains up to 128 glyphs with 1× and 2× bitmap representations. Native table cells reuse image views and read cached images, keeping first-time emoji rasterization out of typing and drawing on the main thread.

Search accepts English and Traditional Chinese simultaneously, ignores case, width and diacritic differences, and treats colons, underscores and hyphens as word separators. Thus `:smile:` works as a convenient keyword spelling and `thumbs_up` matches `thumbs up`; this is not a separate Slack/GitHub shortcode dictionary. Multiple words can match different names or keywords. An exact emoji lookup returns its original fully-qualified sequence, preserving ZWJ, variation-selector and skin-tone scalars for copying. A pasted emoji without its optional emoji variation selector resolves to the same entry.

For text searches, unmodified forms precede skin-tone variants so broad searches are not filled by nearly identical results. Within those groups, exact names, exact keywords, name prefixes, name substrings, and other keyword matches are considered in that order. Ties favor the small common starter set, then CLDR order. Explicit tone queries such as `thumbs up medium skin tone` or `讚 白皮膚` still find the matching variant. Search is deterministic; there is no usage history or remote suggestion service.

An empty feature query shows `😀 😂 ❤️ 👍 🎉 🙏 🔥 ✅ 😊`. This affects the Emoji Search page only; opening Cue's main launcher with no query remains empty. The default search limit is nine, and an input larger than 1,024 UTF-8 bytes yields no results rather than processing pasted prose as a keyword search.

`EmojiCatalogTests` covers the actual bundled repertoire, language coverage, practical queries, tone ranking, literal emoji preservation, normalization, malformed resources, and the fixed default list. Its optimized-build benchmark reports median, p95, and maximum latency over 300 searches against the real catalog; there is no machine-dependent timing assertion.

## 正體中文摘要

Cue 內附 Unicode Emoji 15.0 的 3,655 組完整表情符號，採用固定版本 CLDR 42 的英文及正體中文名稱與關鍵字。膚色、性別、家庭與旗幟組合皆保留完整的 Unicode 序列；畫面由 macOS 系統字型呈現，不下載圖片或字型。所有搜尋皆在本機完成，關閉 Cue 的網路使用仍可正常使用。

資料載入與搜尋索引準備在背景進行，打字時只搜尋已準備的記憶體資料。一般搜尋優先顯示原始形式，避免膚色變體擠滿結果；也可以直接搜尋膚色。支援 `smile`、`開心`、`愛心`、`咖啡`、`台灣`／`臺灣`、`:smile:` 等輸入。官方資料缺少的「黑鳥」名稱及少量常用詞別名由 Cue 補充，來源、修改內容與授權都隨 App 附上。

表情符號的字型載入與圖片繪製也在背景完成，每批最多處理 9 個字形，後續只追蹤最新搜尋結果。快取最多保留 128 個字形的 1×／2× 圖片；原生列表重複使用圖片欄位，避免首次繪製字形拖慢打字。

一般使用者自行編譯時直接使用儲存庫內的資料，不需要執行產生腳本或下載資料。只有維護者重新產生資料時才需 Python 3；加上 `--download` 才會下載固定來源，所有來源均驗證 SHA-256。
