# Chinese conversion data / 中文轉換資料

Cue converts text offline using dictionary data from **OpenCC 1.4.2**, pinned to
commit [`025f371dc76b598d77384fbdab90c937471844d8`](https://github.com/BYVoid/OpenCC/tree/025f371dc76b598d77384fbdab90c937471844d8).
The app includes a native Swift converter and a precompiled data file. Ordinary
source builds need only the tools in [building.md](building.md); users do not
need to install OpenCC, Python, CMake, or a separate conversion service.

Cue 使用 OpenCC 1.4.2 的詞庫，在本機離線轉換文字。轉換包含字形及詞庫收錄的
地區用語，例如「软件／軟體」、「鼠标／滑鼠」、「内存／記憶體」。一般建置直接使用
已附上的資料檔，不需要額外安裝 OpenCC、Python 或 CMake，也不會傳送所選文字。

## Conversion contract

- **Traditional Chinese (Taiwan):** upstream
  [`s2twp.json`](https://github.com/BYVoid/OpenCC/blob/025f371dc76b598d77384fbdab90c937471844d8/data/config/s2twp.json).
- **Simplified Chinese (Mainland terms):** upstream
  [`tw2sp.json`](https://github.com/BYVoid/OpenCC/blob/025f371dc76b598d77384fbdab90c937471844d8/data/config/tw2sp.json).
- Apply OpenCC's compatibility-ideograph normalization before segmentation.
  Do not apply general Unicode normalization: Latin combining marks, emoji,
  punctuation, whitespace, line endings, and unmapped scalars remain intact.
- Use maximum forward phrase matching, retaining consecutive unmatched runs.
  Preserve those segment boundaries through every later conversion stage.
- Union dictionary groups choose the longest prefix across their dictionaries;
  earlier dictionaries win equal-key ties. Short-circuit groups choose the first
  dictionary with a match, even when a later dictionary has a longer match.
- Preserve upstream dictionary order and its **first/default output candidate**
  when a source word has multiple possibilities. This is dictionary conversion,
  so names, context-dependent meanings, and words outside the dictionaries can
  still need manual review.
- Follow OpenCC's default exclusion of the optional `TSCharactersExt` dictionary
  marked `may_output_tofu`, which can produce characters unavailable in fonts.
- Preserve complete unmatched ideographic description sequences using the same
  16-level / 64-scalar bounds as OpenCC.
- Cue additionally preserves embedded NUL scalars, rejects selections larger
  than **256 KiB in UTF-8**, and supports cancellation without returning partial
  replacement text.

Algorithm references:
[`MaxMatchSegmentation.cpp`](https://github.com/BYVoid/OpenCC/blob/025f371dc76b598d77384fbdab90c937471844d8/src/MaxMatchSegmentation.cpp),
[`Conversion.cpp`](https://github.com/BYVoid/OpenCC/blob/025f371dc76b598d77384fbdab90c937471844d8/src/Conversion.cpp),
[`DictGroup.cpp`](https://github.com/BYVoid/OpenCC/blob/025f371dc76b598d77384fbdab90c937471844d8/src/DictGroup.cpp),
[`UTF8Util.hpp`](https://github.com/BYVoid/OpenCC/blob/025f371dc76b598d77384fbdab90c937471844d8/src/UTF8Util.hpp).

## Storage and responsiveness

`Sources/Cue/Resources/ChineseConversion.cuecc` contains **3,178,020 bytes** of
metadata, flat trie nodes/edges, and deduplicated Unicode-scalar output data.
Compared with parsing text dictionaries into thousands of Swift objects, this
uses predictable contiguous storage and little initialization work. Loading and
conversion belong on the background executor, first used only when a conversion
command runs; launcher startup, typing, and ranking do not load these tables.

The immutable converter can be reused for either direction. It performs no
network requests, file writes, subprocess launches, or clipboard operations.
Input and output strings are owned by the caller and are not retained as history.

## Reproducing the checked-in resource

These are maintainer steps only. CMake and a C++ compiler are required to build
the official reference converter, which also generates upstream's regional
phrase and reversed-variant dictionaries. All work stays under ignored `.build`.

```sh
git clone --depth 1 --branch ver.1.4.2 \
  https://github.com/BYVoid/OpenCC.git .build/opencc-upstream-1.4.2
cmake -S .build/opencc-upstream-1.4.2 -B .build/opencc-reference-build \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_OPENCC_JIEBA_PLUGIN=OFF -DENABLE_GTEST=OFF \
  -DBUILD_DOCUMENTATION=OFF -DOPENCC_ENABLE_INSTALL=OFF \
  -DPython3_EXECUTABLE=/usr/bin/python3
cmake --build .build/opencc-reference-build --parallel 4
python3 scripts/prepare-chinese-conversion.py \
  --upstream .build/opencc-upstream-1.4.2 \
  --build .build/opencc-reference-build
```

The generator rejects a different upstream commit or modified tracked source
data. `scripts/chinese-conversion-data.json` records every input SHA-256,
dictionary entry count, binary dimensions, and the output SHA-256. The current
binary hash is:

```text
b21b83f6b708207b2ee15408284311b3be6ee9f6e09d8b8004ebc6057397eff3
```

## Verification

```sh
python3 scripts/verify-chinese-conversion.py \
  --upstream .build/opencc-upstream-1.4.2 \
  --build .build/opencc-reference-build
```

The verifier checks all recorded hashes, compiles Cue's converter with
optimization, and compares **120,092 distinct dictionary and context cases in
each direction** byte-for-byte with the official OpenCC executable. The corpus
includes all source keys and output alternatives, ambiguous characters, regional
phrases, deterministic adjacent/mixed phrase combinations, emoji, supplementary
characters, and ideographic description sequences. Core unit tests additionally
cover multiline/CRLF/NUL preservation, cancellation, input bounds, and malformed
resources.

On the development Apple-silicon Mac with Xcode 27, initial converter construction
took approximately **3.6–6.7 ms**. In an optimized in-memory run, conversion p95
was **0.013 ms for 96 bytes** and **11.2 ms for 96 KiB**. These are in-memory
conversion timings, not end-to-end selection/accessibility latency or guarantees for
other Macs. The verification command reproduces measurements locally.

## License and attribution

OpenCC data and relevant algorithm references are licensed under
[Apache-2.0](../Sources/Cue/Resources/OpenCC-LICENSE.txt), copyright 2010–2026 Carbo
Kuo and contributors. The app includes the complete license and
[OpenCC-NOTICE.txt](../Sources/Cue/Resources/OpenCC-NOTICE.txt). Cue changes the data
representation and implements the conversion in Swift; it does not modify the
upstream phrase choices.
