#!/usr/bin/env python3

import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "results"

BACKENDS = {"vmlx", "lmstudio"}
PROMPTS = {"coding", "architecture", "json"}
REPS = 3

groups = defaultdict(list)

for run_dir in ROOT.iterdir():
    if not run_dir.is_dir():
        continue

    parts = run_dir.name.split("-")

    # YYYYMMDD-HHMMSS-backend-prompt
    if len(parts) < 4:
        continue

    backend = parts[2]
    prompt = "-".join(parts[3:])

    if backend not in BACKENDS or prompt not in PROMPTS:
        continue

    summary = run_dir / "summary.json"
    answer = run_dir / "answer.md"

    if summary.exists() and answer.exists():
        groups[(backend, prompt)].append(run_dir)

selected = []

for backend in sorted(BACKENDS):
    for prompt in sorted(PROMPTS):
        runs = sorted(
            groups[(backend, prompt)],
            key=lambda p: p.name,
            reverse=True,
        )[:REPS]

        if len(runs) != REPS:
            raise SystemExit(
                f"Expected {REPS} runs for {backend}/{prompt}, "
                f"found {len(runs)}"
            )

        for run in reversed(runs):
            selected.append({
                "backend": backend,
                "prompt": prompt,
                "run_dir": str(run),
            })

manifest = {
    "name": "qwen3-coder-next-baseline-matrix",
    "repetitions": REPS,
    "runs": selected,
}

out = ROOT.parent / "current-batch.json"
out.write_text(json.dumps(manifest, indent=2) + "\n")

print(f"Wrote {out}")
print()

for x in selected:
    print(
        f"{x['backend']:<10} "
        f"{x['prompt']:<14} "
        f"{Path(x['run_dir']).name}"
    )
