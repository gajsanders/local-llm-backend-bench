#!/usr/bin/env python3

import json
import statistics
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

manifest = json.loads(
    (ROOT / "current-batch.json").read_text()
)

rows = []

for item in manifest["runs"]:
    run = Path(item["run_dir"])
    summary = json.loads((run / "summary.json").read_text())

    rows.append({
        "backend": item["backend"],
        "prompt": item["prompt"],
        "load": summary.get("load_seconds"),
        "generation": summary.get("generation_wall_seconds"),
        "tokens": summary.get("completion_tokens"),
        "tps": summary.get("wall_completion_tokens_per_second"),
    })

groups = defaultdict(list)

for row in rows:
    groups[(row["prompt"], row["backend"])].append(row)

def med(group, key):
    vals = [x[key] for x in group if x[key] is not None]
    return statistics.median(vals)

print()
print("BASELINE MATRIX — MEDIANS")
print()

print(
    f"{'Prompt':<15}"
    f"{'Backend':<11}"
    f"{'Runs':>5}"
    f"{'Load(s)':>11}"
    f"{'Gen(s)':>11}"
    f"{'Tok/s':>11}"
    f"{'Out tok':>10}"
)

print("-" * 74)

for prompt in ("architecture", "coding", "json"):
    for backend in ("lmstudio", "vmlx"):
        g = groups[(prompt, backend)]

        print(
            f"{prompt:<15}"
            f"{backend:<11}"
            f"{len(g):>5}"
            f"{med(g, 'load'):>11.3f}"
            f"{med(g, 'generation'):>11.3f}"
            f"{med(g, 'tps'):>11.3f}"
            f"{med(g, 'tokens'):>10.0f}"
        )

print()
print("vMLX RELATIVE THROUGHPUT")
print()

ratios = []

for prompt in ("architecture", "coding", "json"):
    v = med(groups[(prompt, "vmlx")], "tps")
    l = med(groups[(prompt, "lmstudio")], "tps")
    ratio = v / l
    ratios.append(ratio)

    print(
        f"{prompt:<15} "
        f"{ratio:.3f}x "
        f"({(ratio - 1) * 100:.1f}% faster)"
    )

print()
print(
    "Median cross-task relative throughput: "
    f"{statistics.median(ratios):.3f}x"
)
