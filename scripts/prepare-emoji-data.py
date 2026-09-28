#!/usr/bin/env python3
"""Prepare Cue's offline emoji catalog from pinned, hash-verified Unicode data.

Ordinary builds use checked-in resources and never run this script or download
emoji data. Pass --download explicitly to fetch the maintainer inputs.
"""
import argparse
import hashlib
import json
import re
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CLDR_COMMIT = "f800890ea86482c2eb5f73224897f4a8bc0b653a"
CLDR_BASE = f"https://raw.githubusercontent.com/unicode-org/cldr/{CLDR_COMMIT}"
SOURCES = {
    "emoji-test.txt": (
        "https://www.unicode.org/Public/emoji/15.0/emoji-test.txt",
        "8445f23ac8388e096be19d0262e14fceff856ff52093f2356dc89485f1a853db",
    ),
    "annotations-en.xml": (
        f"{CLDR_BASE}/common/annotations/en.xml",
        "0e94fb130a1c554da31e49e48e45d7ef30727c1c0ea7b645a009239a6a7081f7",
    ),
    "annotations-zh_Hant.xml": (
        f"{CLDR_BASE}/common/annotations/zh_Hant.xml",
        "ca3b5553a153308ab455b6566fc5dc52e002b2fe9eb50114c8c3c100105ddc67",
    ),
    "derived-en.xml": (
        f"{CLDR_BASE}/common/annotationsDerived/en.xml",
        "cc7d30dc336d89c1d4c97d297f34d645b129f7463632ff9ab44277e4edb1ae97",
    ),
    "derived-zh_Hant.xml": (
        f"{CLDR_BASE}/common/annotationsDerived/zh_Hant.xml",
        "67b6c334f07252374ffd395926b47353c402bc27f3f219ae6fbbfa78fd6b0438",
    ),
    "unicode-license.txt": (
        f"{CLDR_BASE}/unicode-license.txt",
        "e6795346adb86b0fcd0df1fdeadbdbbf5276520e85fdf3d268a1196b532131ba",
    ),
}

# Small Cue-maintained search conveniences, separate from the official names.
# These are not an alternate shortcode standard and never change copied text.
EXTRA_KEYWORDS = {
    "😀": ["happy", "開心"],
    "😃": ["happy", "開心"],
    "😄": ["happy", "開心"],
    "😊": ["happy", "開心"],
    "🥳": ["慶祝", "派對"],
    "🎉": ["慶祝", "派對"],
    "🎊": ["慶祝", "派對"],
    "🇹🇼": ["Taiwan", "台灣", "臺灣"],
}
TRADITIONAL_NAME_PATCHES = {"🐦‍⬛": "黑鳥"}
HEARTS = ("❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "🩷", "🩵", "🩶",
          "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "❤️‍🔥", "❤️‍🩹")


def emoji_key(value):
    return value.replace("\ufe0f", "")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=REPO / ".build/emoji-upstream")
    parser.add_argument("--output-dir", type=Path, default=REPO / "Sources/Cue/Resources")
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()
    args.source_dir.mkdir(parents=True, exist_ok=True)
    inputs = {}
    for filename, (url, expected) in SOURCES.items():
        source = args.source_dir / filename
        if args.download and not source.exists():
            with urllib.request.urlopen(url, timeout=60) as response:
                raw = response.read(4 * 1024 * 1024 + 1)
            if len(raw) > 4 * 1024 * 1024:
                raise SystemExit(f"Oversized upstream input: {filename}")
            if hashlib.sha256(raw).hexdigest() != expected:
                raise SystemExit(f"Unexpected upstream hash: {filename}")
            source.write_bytes(raw)
        raw = source.read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise SystemExit(f"Source hash mismatch: {source}")
        inputs[filename] = raw

    annotations = {}
    for language in ("en", "zh_Hant"):
        records = {}
        for kind in ("annotations", "derived"):
            for annotation in ET.fromstring(inputs[f"{kind}-{language}.xml"]).findall(".//annotation"):
                key = emoji_key(annotation.attrib["cp"])
                text = annotation.text or ""
                if text in ("↑↑↑", "∅∅∅"):
                    raise SystemExit(f"Unresolved annotation inheritance: {language} {key}")
                records.setdefault(key, {})[annotation.get("type", "keywords")] = text
        annotations[language] = records

    entries = []
    patched = []
    for line in inputs["emoji-test.txt"].decode("utf-8").splitlines():
        match = re.match(r"^([0-9A-F ]+)\s*; fully-qualified\s*# (\S+) E[0-9.]+ (.+)$", line)
        if not match:
            continue
        emoji = "".join(chr(int(codepoint, 16)) for codepoint in match[1].split())
        key = emoji_key(emoji)
        english = annotations["en"].get(key, {})
        traditional = annotations["zh_Hant"].get(key, {})
        name = english.get("tts")
        traditional_name = traditional.get("tts")
        if not traditional_name and key in TRADITIONAL_NAME_PATCHES:
            traditional_name = TRADITIONAL_NAME_PATCHES[key]
            patched.append(key)
        if not name or not traditional_name:
            raise SystemExit(f"Missing name for {emoji}: {name!r} / {traditional_name!r}")
        keywords = english.get("keywords", "").split(" | ")
        keywords += traditional.get("keywords", "").split(" | ")
        keywords += EXTRA_KEYWORDS.get(key, [])
        if key in {emoji_key(heart) for heart in HEARTS}:
            keywords += ["愛心"]
        if key in TRADITIONAL_NAME_PATCHES:
            keywords += ["鳥", "黑色"]
        keywords = list(dict.fromkeys(word for word in keywords if word))
        entries.append({"emoji": emoji, "name": name, "traditionalName": traditional_name, "keywords": keywords})

    if len(entries) != 3655 or len({entry["emoji"] for entry in entries}) != 3655:
        raise SystemExit("Unexpected Emoji 15.0 repertoire count or duplicate entries")
    if set(patched) != set(TRADITIONAL_NAME_PATCHES):
        raise SystemExit("Upstream translations changed; revisit Cue's explicit name patches")
    catalog = {"formatVersion": 1, "unicodeVersion": "15.0", "cldrVersion": "42", "entries": entries}
    raw = (json.dumps(catalog, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "EmojiCatalog.json").write_bytes(raw)
    (args.output_dir / "Unicode-LICENSE.txt").write_bytes(inputs["unicode-license.txt"])
    notice = f"""Cue offline emoji catalog

Derived from Unicode Emoji 15.0 and CLDR 42 English/Traditional Chinese data.
Copyright © 1991-2022 Unicode, Inc. All rights reserved.
Unicode data license: see Unicode-LICENSE.txt in this bundle.

Emoji repertoire: https://www.unicode.org/Public/emoji/15.0/emoji-test.txt
CLDR release: https://cldr.unicode.org/downloads/cldr-42
CLDR commit: {CLDR_COMMIT}
Annotations: common/annotations and common/annotationsDerived, en and zh_Hant.

Cue modifications: combine names and keywords into a compact local catalog;
keep only the 3,655 fully-qualified Emoji 15.0 entries; add a Traditional
Chinese name for black bird (黑鳥) missing in CLDR 42; add common English
and Taiwan search aliases for happy, celebration, Taiwan, and heart shapes. No emoji
artwork is included: macOS renders each Unicode sequence using its fonts.

Reproduction and source hashes: scripts/prepare-emoji-data.py and
docs/emoji-data.md in https://github.com/hsiuhsiu/cue.
"""
    (args.output_dir / "Emoji-NOTICE.txt").write_text(notice, encoding="utf-8")
    print(f"Generated {len(entries)} emoji; {len(raw):,} bytes; all English and Traditional Chinese names present")
    print(f"EmojiCatalog.json SHA-256: {hashlib.sha256(raw).hexdigest()}")


if __name__ == "__main__":
    main()
