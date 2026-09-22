#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCH="$SCRIPT_DIR/bench.sh"

PROMPTS=(
    coding
    architecture
    json
)

BACKENDS=(
    vmlx-simple
    vmlx-continuous
)

REPETITIONS=3

BATCH_ID="$(date '+%Y%m%d-%H%M%S')"
MANIFEST="$ROOT/results/vmlx-profile-matrix-${BATCH_ID}.txt"

TOTAL=$(( ${#PROMPTS[@]} * ${#BACKENDS[@]} * REPETITIONS ))
RUN_NUM=0

echo "========================================"
echo " vMLX Profile Benchmark Matrix"
echo "========================================"
echo
echo "Batch:        $BATCH_ID"
echo "Prompts:      ${PROMPTS[*]}"
echo "Profiles:     ${BACKENDS[*]}"
echo "Repetitions:  $REPETITIONS"
echo "Total runs:   $TOTAL"
echo

touch "$MANIFEST"

for prompt in "${PROMPTS[@]}"; do
    for backend in "${BACKENDS[@]}"; do
        for rep in $(seq 1 "$REPETITIONS"); do

            RUN_NUM=$((RUN_NUM + 1))

            echo
            echo "========================================"
            echo " Run $RUN_NUM / $TOTAL"
            echo "========================================"
            echo "Prompt:      $prompt"
            echo "Profile:     $backend"
            echo "Repetition:  $rep"
            echo

            BEFORE="$(
                ls -td "$ROOT"/results/*-"$backend"-"$prompt" \
                2>/dev/null | head -1 || true
            )"

            "$BENCH" "$backend" "$prompt"

            AFTER="$(
                ls -td "$ROOT"/results/*-"$backend"-"$prompt" \
                2>/dev/null | head -1 || true
            )"

            if [[ -z "$AFTER" || "$AFTER" == "$BEFORE" ]]; then
                echo "ERROR: could not identify newly created run."
                exit 1
            fi

            echo "$AFTER" >> "$MANIFEST"

            echo
            echo "Cooling down for 5 seconds..."
            sleep 5
        done
    done
done

echo
echo "========================================"
echo " Matrix complete"
echo "========================================"
echo
echo "Manifest:"
echo "  $MANIFEST"
