#!/usr/bin/env python3

import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"

if len(sys.argv) > 1:
    manifest = Path(sys.argv[1])
else:
    manifests = sorted(
        RESULTS.glob("vmlx-profile-matrix-*.txt"),
        reverse=True,
    )

    manifests = [
        p for p in manifests
        if p.read_text().strip()
    ]

    if not manifests:
        raise SystemExit("No completed vMLX profile matrix manifest found.")

    manifest = manifests[0]

runs = [
    Path(line.strip())
    for line in manifest.read_text().splitlines()
    if line.strip()
]

rows = []

for run in runs:
    summary = json.loads((run / "summary.json").read_text())

    backend = summary["backend"]

    prompt = summary.get("prompt")

    if not prompt:
        # Compatibility with older summaries.
        name = run.name
        for candidate in ("coding", "architecture", "json"):
            if name.endswith("-" + candidate):
                prompt = candidate
                break

    rows.append({
        "backend": backend,
        "prompt": prompt,
        "load": summary["load_seconds"],
        "generation": summary["generation_wall_seconds"],
        "tokens": summary["completion_tokens"],
        "tps": summary["wall_completion_tokens_per_second"],
        "reported_tps": summary.get("vmlx_reported_decode_tps"),
    })

groups = defaultdict(list)

for row in rows:
    groups[(row["prompt"], row["backend"])].append(row)


def med(group, key):
    vals = [
        x[key]
        for x in group
        if isinstance(x.get(key), (int, float))
    ]
    return statistics.median(vals)


print()
print(f"Manifest: {manifest.name}")
print()
print("vMLX PROFILE MATRIX — MEDIANS")
print()

header = (
    f"{'Prompt':<15}"
    f"{'Profile':<18}"
    f"{'Runs':>5}"
    f"{'Load(s)':>11}"
    f"{'Gen(s)':>11}"
    f"{'Wall tok/s':>13}"
    f"{'Decode':>11}"
    f"{'Out tok':>10}"
)

print(header)
print("-" * len(header))

for prompt in ("architecture", "coding", "json"):
    for backend in ("vmlx-simple", "vmlx-continuous"):

        group = groups[(prompt, backend)]

        print(
            f"{prompt:<15}"
            f"{backend:<18}"
            f"{len(group):>5}"
            f"{med(group, 'load'):>11.3f}"
            f"{med(group, 'generation'):>11.3f}"
            f"{med(group, 'tps'):>13.3f}"
            f"{med(group, 'reported_tps'):>11.3f}"
            f"{med(group, 'tokens'):>10.0f}"
        )

print()
print("SIMPLE vs CONTINUOUS")
print()

ratios = []

for prompt in ("architecture", "coding", "json"):

    simple = med(groups[(prompt, "vmlx-simple")], "reported_tps")
    continuous = med(
        groups[(prompt, "vmlx-continuous")],
        "reported_tps",
    )

    ratio = simple / continuous
    ratios.append(ratio)

    if ratio >= 1:
        print(
            f"{prompt:<15} simple is "
            f"{(ratio - 1) * 100:.1f}% faster"
        )
    else:
        print(
            f"{prompt:<15} continuous is "
            f"{((1 / ratio) - 1) * 100:.1f}% faster"
        )

median_ratio = statistics.median(ratios)

print()

if median_ratio >= 1:
    print(
        "Cross-task median: simple is "
        f"{(median_ratio - 1) * 100:.1f}% faster"
    )
else:
    print(
        "Cross-task median: continuous is "
        f"{((1 / median_ratio) - 1) * 100:.1f}% faster"
    )
