#!/usr/bin/env python3
"""Compare Cue's converter against the pinned, locally built official OpenCC CLI."""
import argparse
import hashlib
import json
import random
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--work", type=Path, default=ROOT / ".build/chinese-conversion-check")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ROOT / "scripts/chinese-conversion-data.json").read_text())
    artifact = ROOT / "Sources/Cue/Resources/ChineseConversion.cuecc"
    assert hashlib.sha256(artifact.read_bytes()).hexdigest() == manifest["artifactSHA256"]
    corpus = {"", "头发发展，干燥干杯干活，皇后后面，面条里面。", "SQL注入攻击与数据库连接池",
              "滑鼠和記憶體；鼠标和内存；軟件與打印機。", "⿰髟发和头发，⿱艹⿰氵台软件。",
              "😀👩‍💻 軟體 Aé e\u0301 ℌ 𝕏 神 車 𠀀　", "两百个新发现的数据库软件包", "乒乓球拍卖完了"}
    for relative, expected in manifest["sourceSHA256"].items():
        if relative.startswith("generated/"):
            path = args.build / "data" / Path(relative).name
        else:
            path = args.upstream / relative
        raw = path.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == expected, f"Changed source: {relative}"
        if not relative.endswith(".txt"):
            continue
        for line in raw.decode().splitlines():
            if not line or line.startswith("#"):
                continue
            key, values = line.split("\t", 1)
            corpus.add(key)
            corpus.update(values.split())
    words = sorted(corpus - {""})
    randomizer = random.Random(0xC0ECC)
    for _ in range(10_000):
        a, b, c = randomizer.choices(words, k=3)
        corpus.add(a + b + c)
        corpus.add(a + "，" + b + "😀" + c)
    corpus = sorted(corpus)
    input_path = args.work / "corpus.txt"
    input_path.write_text("\n".join(corpus) + "\n")
    runner = args.work / "verify"
    subprocess.run(["xcrun", "swiftc", "-O", "-swift-version", "6", "-module-cache-path", str(args.work / "cache"),
                    str(ROOT / "Sources/CueCore/ChineseConversion.swift"),
                    str(ROOT / "scripts/verify-chinese-conversion.swift"), "-o", str(runner)], check=True)
    for target, config in [("traditionalTaiwan", "s2twp"), ("simplifiedChina", "tw2sp")]:
        actual = args.work / f"{target}.txt"
        expected = args.work / f"{target}-opencc.txt"
        subprocess.run([str(runner), str(artifact), target, str(input_path), str(actual)], check=True)
        subprocess.run([str(args.build / "src/tools/opencc"), "-c", str(args.upstream / f"data/config/{config}.json"),
                        "--path", str(args.build / "data"), "-i", str(input_path), "-o", str(expected)], check=True)
        if actual.read_bytes() != expected.read_bytes():
            differences = [(source, a, b) for source, a, b in zip(corpus, actual.read_text().splitlines(), expected.read_text().splitlines()) if a != b]
            raise SystemExit(f"FAIL {target}: {len(differences)} differences; first: {differences[:10]}")
        print(f"PASS {target}: {len(corpus):,} dictionary/context cases match official OpenCC byte-for-byte")
    subprocess.run([str(runner), str(artifact), "--benchmark"], check=True)


if __name__ == "__main__":
    main()
