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


def iqr(group, key):
    vals = sorted([x[key] for x in group if x[key] is not None])
    if len(vals) < 4:
        return None
    q1_idx = (len(vals) - 1) // 4
    q3_idx = (3 * (len(vals) - 1)) // 4
    return vals[q3_idx] - vals[q1_idx]

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

        load_med = med(g, 'load')
        gen_med = med(g, 'generation')
        tps_med = med(g, 'tps')
        tok_med = med(g, 'tokens')

        load_iqr = iqr(g, 'load')
        gen_iqr = iqr(g, 'generation')
        tps_iqr = iqr(g, 'tps')

        load_str = f"{load_med:.3f}" + (f" (IQR: {load_iqr:.3f})" if load_iqr is not None else "")
        gen_str = f"{gen_med:.3f}" + (f" (IQR: {gen_iqr:.3f})" if gen_iqr is not None else "")
        tps_str = f"{tps_med:.3f}" + (f" (IQR: {tps_iqr:.3f})" if tps_iqr is not None else "")

        print(
            f"{prompt:<15}"
            f"{backend:<11}"
            f"{len(g):>5}"
            f"{load_str:>11}"
            f"{gen_str:>11}"
            f"{tps_str:>11}"
            f"{tok_med:>10.0f}"
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

print()
print("IQR dispersion (Interquartile Range) is shown where n >= 4 repetitions are available.")
print("With n=3, IQR cannot be computed and only medians are reported.")

