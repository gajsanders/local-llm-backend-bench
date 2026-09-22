#!/usr/bin/env python3

import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

manifest = json.loads(
    (ROOT / "current-batch.json").read_text()
)

rows = []


def coding_score(text):
    lower = text.lower()

    checks = {
        "off_by_one": (
            "off-by-one" in lower
            or "off by one" in lower
            or "excludes the current" in lower
        ),
        "invalid_window": (
            "window <= 0" in lower
            or "window must be a positive" in lower
            or (
                "window = 0" in lower
                and "window < 0" in lower
            )
        ),
        "complexity": (
            "o(n·window)" in lower
            or "o(n*window)" in lower
            or "o(nw)" in lower
            or "o(n · window)" in lower
        ),
        "linear_fix": (
            "deque" in lower
            or "running sum" in lower
            or "sliding window" in lower
        ),
    }

    test_count = len(
        re.findall(r"\bdef\s+test_[A-Za-z0-9_]+\s*\(", text)
    )

    checks["five_tests"] = test_count == 5

    return checks


def json_score(text):
    result = {
        "valid_json": False,
        "exact_top_level_keys": False,
        "at_least_four_bugs": False,
        "exactly_five_tests": False,
        "replacement_code_present": False,
    }

    try:
        obj = json.loads(text)
    except Exception:
        return result

    result["valid_json"] = True

    expected = {
        "bugs",
        "recommended_changes",
        "tests",
        "replacement_code",
    }

    result["exact_top_level_keys"] = set(obj.keys()) == expected

    bugs = obj.get("bugs")
    tests = obj.get("tests")
    replacement = obj.get("replacement_code")

    result["at_least_four_bugs"] = (
        isinstance(bugs, list) and len(bugs) >= 4
    )

    result["exactly_five_tests"] = (
        isinstance(tests, list) and len(tests) == 5
    )

    result["replacement_code_present"] = (
        isinstance(replacement, str)
        and len(replacement.strip()) > 40
        and "def retry_request" in replacement
    )

    return result


def architecture_score(text):
    lower = text.lower()

    checks = {
        "problems_section": any(
            x in lower
            for x in [
                "architectural problem",
                "architecture problem",
                "problems",
            ]
        ),
        "target_architecture": (
            "target architecture" in lower
            or "proposed architecture" in lower
            or "layer" in lower
        ),
        "shared_vs_model_specific": (
            "model-specific" in lower
            or "model specific" in lower
        ),
        "package_structure": (
            "package" in lower
            or "module structure" in lower
            or "src/" in lower
        ),
        "migration_strategy": (
            "migration" in lower
            or "incremental" in lower
        ),
        "do_not_generalize": (
            "do not generalize" in lower
            or "not generalize" in lower
            or "remain model-specific" in lower
        ),
    }

    return checks


for item in manifest["runs"]:
    run = Path(item["run_dir"])
    answer = (run / "answer.md").read_text(errors="replace")

    prompt = item["prompt"]

    if prompt == "coding":
        checks = coding_score(answer)
    elif prompt == "json":
        checks = json_score(answer)
    elif prompt == "architecture":
        checks = architecture_score(answer)
    else:
        continue

    passed = sum(bool(x) for x in checks.values())
    total = len(checks)

    rows.append({
        "backend": item["backend"],
        "prompt": prompt,
        "run": run.name,
        "passed": passed,
        "total": total,
        "score_pct": round(100 * passed / total, 1),
        "checks": checks,
    })


grouped = defaultdict(list)

for row in rows:
    grouped[(row["backend"], row["prompt"])].append(row)


print()
print("QUALITY RESULTS")
print()

header = (
    f"{'Prompt':<15}"
    f"{'Backend':<11}"
    f"{'Runs':>5}"
    f"{'Avg %':>9}"
    f"{'Perfect':>10}"
)

print(header)
print("-" * len(header))

for prompt in ["coding", "architecture", "json"]:
    for backend in ["lmstudio", "vmlx"]:
        group = grouped[(backend, prompt)]

        avg = sum(x["score_pct"] for x in group) / len(group)
        perfect = sum(x["passed"] == x["total"] for x in group)

        print(
            f"{prompt:<15}"
            f"{backend:<11}"
            f"{len(group):>5}"
            f"{avg:>9.1f}"
            f"{perfect:>7}/{len(group)}"
        )

print()
print("INDIVIDUAL FAILURES")
print()

found = False

for row in rows:
    failed = [
        name
        for name, value in row["checks"].items()
        if not value
    ]

    if failed:
        found = True
        print(
            f"{row['backend']:<10} "
            f"{row['prompt']:<14} "
            f"{row['run']}"
        )
        print("  " + ", ".join(failed))

if not found:
    print("None.")

(ROOT / "quality-results.json").write_text(
    json.dumps(rows, indent=2) + "\n"
)

print()
print(
    "Detailed results written to "
    "backend-bench/quality-results.json"
)
