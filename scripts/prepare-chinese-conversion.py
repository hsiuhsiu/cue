#!/usr/bin/env python3
"""Compile pinned OpenCC data into Cue's small, dependency-free scalar tries.

Developer-only; ordinary Cue builds use the checked-in data and need neither
Python nor OpenCC. See docs/chinese-conversion-data.md for reproduction steps.
"""
import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path

COMMIT = "025f371dc76b598d77384fbdab90c937471844d8"
VERSION = "1.4.2"
REPO = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=REPO / "Sources/Cue/Resources/ChineseConversion.cuecc")
    parser.add_argument("--manifest", type=Path, default=REPO / "scripts/chinese-conversion-data.json")
    args = parser.parse_args()
    upstream = args.upstream.resolve()
    build = args.build.resolve()
    actual = subprocess.check_output(["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True).strip()
    if actual != COMMIT:
        raise SystemExit(f"Expected OpenCC commit {COMMIT}; found {actual}")
    subprocess.run(["git", "-C", str(upstream), "diff", "--exit-code", "HEAD", "--", "data", "LICENSE"], check=True)
    hashes = {}
    dictionaries = {}
    # [children by scalar, first output candidate]. Flat nodes avoid thousands of
    # runtime dictionaries/objects and preserve Unicode scalars without NFC folding.
    nodes = []
    roots = {}

    def read_bytes(path, name):
        raw = path.read_bytes()
        hashes[name] = hashlib.sha256(raw).hexdigest()
        return raw

    def dictionary(name):
        if name not in dictionaries:
            path = upstream / "data/dictionary" / f"{name}.txt"
            label = f"data/dictionary/{name}.txt"
            if not path.exists():
                path = build / "data" / f"{name}.txt"
                label = f"generated/{name}.txt"
            entries = {}
            for line in read_bytes(path, label).decode("utf-8").splitlines():
                if not line or line.startswith("#"):
                    continue
                key, values = line.split("\t", 1)
                if key in entries or not key or not values.split():
                    raise ValueError(f"Invalid/duplicate dictionary entry in {name}")
                entries[key] = values.split()[0]  # OpenCC's default ambiguity choice.
            dictionaries[name] = entries
        return dictionaries[name]

    def trie(name, entries):
        if name in roots:
            return roots[name]
        root = len(nodes)
        roots[name] = root
        nodes.append([{}, None])
        for key, value in sorted(entries.items()):
            index = root
            for scalar in map(ord, key):
                child = nodes[index][0].get(scalar)
                if child is None:
                    child = len(nodes)
                    nodes[index][0][scalar] = child
                    nodes.append([{}, None])
                index = child
            nodes[index][1] = tuple(map(ord, value))
        return root

    def group(spec):
        if spec.get("may_output_tofu", False):
            return []  # Match OpenCC's default: extended tofu-risk output is opt-in.
        if spec["type"] == "ocd2":
            name = Path(spec["file"]).stem
            return [trie(name, dictionary(name))]
        if spec["type"] != "group":
            raise ValueError(f"Unsupported dictionary type: {spec}")
        policy = spec.get("match_policy", "short_circuit")
        if policy == "short_circuit":
            return [root for child in spec["dicts"] for root in group(child)]
        if policy != "union" or any(child["type"] != "ocd2" for child in spec["dicts"]):
            raise ValueError(f"Unsupported dictionary group: {spec}")
        names = [Path(child["file"]).stem for child in spec["dicts"]]
        merged = {}
        for name in names:
            for key, value in dictionary(name).items():
                merged.setdefault(key, value)  # Earlier dictionary wins equal-length keys.
        return [trie("union:" + "+".join(names), merged)]

    configurations = {}
    for target, name in [("traditionalTaiwan", "s2twp"), ("simplifiedChina", "tw2sp")]:
        raw = read_bytes(upstream / "data/config" / f"{name}.json", f"data/config/{name}.json")
        config = json.loads(raw)
        if config["segmentation"]["type"] != "mmseg":
            raise ValueError("Unsupported segmentation")
        segmentation = group(config["segmentation"]["dict"])
        if len(segmentation) != 1:
            raise ValueError("Segmentation must have one (possibly union) trie")
        configurations[target] = {
            "normalization": [group(stage["dict"]) for stage in config.get("normalization", [])],
            "segmentation": segmentation[0],
            "stages": [group(stage["dict"]) for stage in config["conversion_chain"]],
        }

    values, edges, node_words = [], [], []
    value_offsets = {}
    for children, value in nodes:
        first_edge = len(edges) // 2
        for scalar, child in sorted(children.items()):
            edges.extend((scalar, child))
        if value:
            if value not in value_offsets:
                value_offsets[value] = len(values)
                values.extend(value)
            offset, length = value_offsets[value], len(value)
        else:
            offset, length = 0, 0
        node_words.extend((first_edge, len(children), offset, length))

    metadata = json.dumps({"version": VERSION, "commit": COMMIT, "configurations": configurations},
                          ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    padding = b"\0" * ((-len(metadata)) % 4)
    header = b"CUECC001" + struct.pack("<4I", len(metadata), len(nodes), len(edges) // 2, len(values))
    payload = node_words + edges + values
    data = header + metadata + padding + struct.pack(f"<{len(payload)}I", *payload)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    license_data = read_bytes(upstream / "LICENSE", "LICENSE")
    (REPO / "Sources/Cue/Resources/OpenCC-LICENSE.txt").write_bytes(license_data)
    manifest = {"upstream": "https://github.com/BYVoid/OpenCC", "version": VERSION, "commit": COMMIT,
                "sourceSHA256": dict(sorted(hashes.items())), "artifactSHA256": hashlib.sha256(data).hexdigest(),
                "artifactBytes": len(data), "nodes": len(nodes), "edges": len(edges) // 2,
                "valueScalars": len(values), "dictionaryEntries": {k: len(v) for k, v in sorted(dictionaries.items())}}
    args.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Wrote {args.output}: {len(data):,} bytes; {len(nodes):,} nodes; SHA256 {manifest['artifactSHA256']}")


if __name__ == "__main__":
    main()
