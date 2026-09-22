#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCH="$ROOT/scripts/bench.sh"

PROMPTS=(
    coding
    architecture
    json
)

BACKENDS=(
    vmlx
    lmstudio
)

REPETITIONS=3

echo "========================================"
echo " Local LLM Backend Benchmark Matrix"
echo "========================================"
echo
echo "Prompts:      ${PROMPTS[*]}"
echo "Backends:     ${BACKENDS[*]}"
echo "Repetitions:  $REPETITIONS"
echo
echo "Total runs: $(( ${#PROMPTS[@]} * ${#BACKENDS[@]} * REPETITIONS ))"
echo

RUN_NUM=0
TOTAL=$(( ${#PROMPTS[@]} * ${#BACKENDS[@]} * REPETITIONS ))

for prompt in "${PROMPTS[@]}"; do
    for backend in "${BACKENDS[@]}"; do
        for rep in $(seq 1 "$REPETITIONS"); do

            RUN_NUM=$((RUN_NUM + 1))

            echo
            echo "========================================"
            echo " Run $RUN_NUM / $TOTAL"
            echo "========================================"
            echo "Prompt:      $prompt"
            echo "Backend:     $backend"
            echo "Repetition:  $rep"
            echo

            "$BENCH" "$backend" "$prompt"

            # Let memory pressure settle slightly between large model loads.
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
