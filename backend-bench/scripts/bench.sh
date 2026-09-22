#!/bin/bash
set -euo pipefail

# ----------------------------------------------------------
# Portable CLI discovery
# ----------------------------------------------------------

# LM Studio commonly installs its CLI under ~/.lmstudio/bin.
# Add it to PATH only if that directory exists.
if [[ -d "$HOME/.lmstudio/bin" ]]; then
    export PATH="$HOME/.lmstudio/bin:$PATH"
fi

# Verify required commands early and give useful errors.
for cmd in python3 curl lsof vm_stat; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $cmd"
        exit 1
    fi
done

BACKEND="${1:-}"
# Process state used by cleanup.
SERVER_PID=""
LOG_PID=""
STARTED_LMS_SERVER=0
CLEANED=0

case "$BACKEND" in
    vmlx-simple|vmlx-continuous|lmstudio)
        ;;
    *)
        echo "Usage:"
        echo "  ./backend-bench/scripts/bench.sh vmlx-simple [prompt]"
        echo "  ./backend-bench/scripts/bench.sh vmlx-continuous [prompt]"
        echo "  ./backend-bench/scripts/bench.sh lmstudio [prompt]"
        exit 2
        ;;
esac

# Check backend-specific CLI only when needed.
if [[ "$BACKEND" == vmlx-* ]]; then
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Stopping vMLX..."
        kill "$SERVER_PID" 2>/dev/null
        wait "$SERVER_PID" 2>/dev/null
    fi
fi

if [[ "$BACKEND" == "lmstudio" ]]; then
    if ! command -v lms >/dev/null 2>&1; then
        echo "ERROR: LM Studio CLI 'lms' not found."
        echo
        echo "Expected locations include:"
        echo "  \$HOME/.lmstudio/bin/lms"
        echo
        echo "Make sure LM Studio is installed and its CLI is available."
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODEL_DIR="${MODEL_DIR:-$HOME/.lmstudio/models/lmstudio-community/Qwen3-Coder-Next-MLX-6bit}"
LM_MODEL_KEY="${LM_MODEL_KEY:-qwen/qwen3-coder-next}"

PROMPT_NAME="${2:-coding}"
PROMPT_FILE="$ROOT/prompts/${PROMPT_NAME}.txt"

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "ERROR: unknown prompt '$PROMPT_NAME'"
    echo "Available prompts:"
    ls "$ROOT/prompts"/*.txt | sed 's#.*/##; s#\.txt$##'
    exit 2
fi

STAMP="$(date '+%Y%m%d-%H%M%S')"
RUN_DIR="$ROOT/results/${STAMP}-${BACKEND}-${PROMPT_NAME}"

mkdir -p "$RUN_DIR"

cleanup() {
    [[ "${CLEANED:-0}" == "1" ]] && return
    CLEANED=1

    (
        set +e

        if [[ -n "${LOG_PID:-}" ]] && kill -0 "${LOG_PID}" 2>/dev/null; then
            kill "${LOG_PID}" 2>/dev/null
            wait "${LOG_PID}" 2>/dev/null
        fi

        if [[ "${BACKEND:-}" == vmlx-* ]]; then
            if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
                echo "Stopping vMLX..."
                kill "${SERVER_PID}" 2>/dev/null
                wait "${SERVER_PID}" 2>/dev/null
            fi
        fi

        if [[ "${BACKEND:-}" == "lmstudio" ]]; then
            echo "Unloading LM Studio benchmark model..."
            lms unload --all >/dev/null 2>&1 || true

            if [[ "${STARTED_LMS_SERVER:-0}" == "1" ]]; then
                echo "Stopping LM Studio server..."
                lms server stop >/dev/null 2>&1 || true
            fi
        fi
    )
}

trap cleanup EXIT INT TERM

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "ERROR: prompt not found:"
    echo "  $PROMPT_FILE"
    exit 1
fi

PROMPT="$(cat "$PROMPT_FILE")"

echo "========================================"
echo " Local LLM Backend Bench — $BACKEND"
echo "========================================"

# ----------------------------------------------------------
# Environment metadata
# ----------------------------------------------------------

{
    echo "date=$(date -Iseconds)"
    echo "backend=$BACKEND"
    echo "macos=$(sw_vers -productVersion)"
    echo "machine=$(uname -m)"
    echo "prompt=$PROMPT_NAME"
} > "$RUN_DIR/environment.txt"

vm_stat > "$RUN_DIR/vm-stat.before.txt"

# ----------------------------------------------------------
# Backend startup
# ----------------------------------------------------------

LOAD_START="$(
python3 - <<'PY'
import time
print(time.time())
PY
)"

if [[ "$BACKEND" == vmlx-* ]]; then

    PORT=8000
    BASE_URL="http://127.0.0.1:8000/v1"
    API_MODEL="lmstudio-community/Qwen3-Coder-Next-MLX-6bit"

    if lsof -tiTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
        echo "ERROR: port $PORT already in use."
        exit 1
    fi

    TEMPLATE="$(cat "$MODEL_DIR/chat_template.jinja")"

    VMLX_MODE_ARGS=()

    case "$BACKEND" in
        vmlx-simple)
            VMLX_MODE_ARGS=(
                --no-continuous-batching
            )
            ;;

        vmlx-continuous)
            VMLX_MODE_ARGS=(
                --continuous-batching
                --max-num-seqs 1
                --disable-prefix-cache
                --no-paged-cache
                --disable-block-disk-cache
            )
            ;;
    esac

    echo "Starting vMLX profile: $BACKEND"

    vmlx serve "$MODEL_DIR" \
        --host 127.0.0.1 \
        --port "$PORT" \
        --max-prompt-tokens 65536 \
        "${VMLX_MODE_ARGS[@]}" \
        --reasoning-parser none \
        --chat-template "$TEMPLATE" \
        --chat-template-kwargs '{"enable_thinking": false}' \
        --default-temperature 0.3 \
        --default-top-p 0.8 \
        --default-top-k 40 \
        --default-repetition-penalty 1.1 \
        --default-enable-thinking false \
        > "$RUN_DIR/backend.log" 2>&1 &

    SERVER_PID=$!

    READY=0

    for _ in $(seq 1 180); do
        if curl -fsS "$BASE_URL/models" >/dev/null 2>&1; then
            READY=1
            break
        fi

        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            echo "ERROR: vMLX exited during startup."
            tail -80 "$RUN_DIR/backend.log"
            exit 1
        fi

        sleep 1
    done

    if [[ "$READY" != "1" ]]; then
        echo "ERROR: vMLX failed to become ready."
        exit 1
    fi

else

    PORT=1234
    BASE_URL="http://127.0.0.1:1234/v1"
    API_MODEL="qwen3-coder-next-bench"

    echo "Preparing LM Studio..."

    # Avoid contaminating the benchmark with an already-loaded model.
    if lms ps 2>/dev/null | grep -qi 'qwen3-coder-next'; then
        echo "ERROR: Qwen3-Coder-Next is already loaded in LM Studio."
        echo "Unload it first with:"
        echo "  lms unload --all"
        exit 1
    fi

    if ! curl -fsS "$BASE_URL/models" >/dev/null 2>&1; then
        echo "Starting LM Studio server..."

        lms server start \
            --port 1234 \
            --bind 127.0.0.1

        STARTED_LMS_SERVER=1
    fi

    echo "Loading model..."

    lms load "$LM_MODEL_KEY" \
        --context-length 65536 \
        --gpu max \
        --identifier "$API_MODEL"

    # Capture inference statistics.
    lms log stream \
        --source model \
        --filter output \
        --stats \
        --json \
        > "$RUN_DIR/backend.log" 2>&1 &

    LOG_PID=$!

    sleep 1
fi

LOAD_END="$(
python3 - <<'PY'
import time
print(time.time())
PY
)"

LOAD_SECONDS="$(
python3 - <<PY
print(round(float("$LOAD_END") - float("$LOAD_START"), 3))
PY
)"

echo "Backend ready in ${LOAD_SECONDS}s"

curl -fsS "$BASE_URL/models" \
    > "$RUN_DIR/models.json"

vm_stat > "$RUN_DIR/vm-stat.loaded.txt"

# ----------------------------------------------------------
# Build identical API request
# ----------------------------------------------------------

python3 - "$PROMPT_FILE" "$API_MODEL" "$RUN_DIR/request.json" <<'PY'
import json
import sys
from pathlib import Path

prompt = Path(sys.argv[1]).read_text()
model = sys.argv[2]
out = Path(sys.argv[3])

request = {
    "model": model,
    "messages": [
        {
            "role": "user",
            "content": prompt
        }
    ],
    "temperature": 0.3,
    "top_p": 0.8,
    "max_tokens": 4096,
    "stream": False
}

out.write_text(json.dumps(request, indent=2) + "\n")
PY

# ----------------------------------------------------------
# Inference
# ----------------------------------------------------------

echo
echo "Running generation..."

GEN_START="$(
python3 - <<'PY'
import time
print(time.time())
PY
)"

HTTP_CODE="$(
curl -sS \
    -o "$RUN_DIR/response.json" \
    -w '%{http_code}' \
    "$BASE_URL/chat/completions" \
    -H 'Content-Type: application/json' \
    --data-binary "@$RUN_DIR/request.json"
)"

GEN_END="$(
python3 - <<'PY'
import time
print(time.time())
PY
)"

GEN_SECONDS="$(
python3 - <<PY
print(round(float("$GEN_END") - float("$GEN_START"), 3))
PY
)"

vm_stat > "$RUN_DIR/vm-stat.after.txt"

echo "HTTP status: $HTTP_CODE"
echo "Generation wall time: ${GEN_SECONDS}s"

if [[ "$HTTP_CODE" != "200" ]]; then
    echo
    echo "ERROR: inference request failed."
    cat "$RUN_DIR/response.json"
    exit 1
fi

# Give LM Studio logger a moment to flush.
sleep 1

# ----------------------------------------------------------
# Summarize
# ----------------------------------------------------------

python3 - \
    "$RUN_DIR" \
    "$BACKEND" \
    "$PROMPT_NAME" \
    "$LOAD_SECONDS" \
    "$GEN_SECONDS" <<'PY'
import json
import re
import sys
from pathlib import Path

run = Path(sys.argv[1])
backend = sys.argv[2]
prompt = sys.argv[3]
load_seconds = float(sys.argv[4])
generation_seconds = float(sys.argv[5])

response = json.loads((run / "response.json").read_text())

choice = response.get("choices", [{}])[0]
message = choice.get("message", {})
answer = message.get("content", "") or ""

usage = response.get("usage", {}) or {}

prompt_tokens = (
    usage.get("prompt_tokens")
    or usage.get("input_tokens")
    or 0
)

completion_tokens = (
    usage.get("completion_tokens")
    or usage.get("output_tokens")
    or 0
)

total_tokens = usage.get("total_tokens") or (
    prompt_tokens + completion_tokens
)

wall_decode_tps = None

if generation_seconds > 0 and completion_tokens:
    wall_decode_tps = round(
        completion_tokens / generation_seconds,
        2
    )

backend_log = (
    (run / "backend.log").read_text(errors="replace")
    if (run / "backend.log").exists()
    else ""
)

# vMLX exact decode reporting.
vmlx_matches = re.findall(
    r"Chat completion.*?:\s*(\d+)\s+tokens in\s+([0-9.]+)s",
    backend_log
)

vmlx_decode_tps = None

if vmlx_matches:
    tokens = sum(int(x) for x, _ in vmlx_matches)
    seconds = sum(float(x) for _, x in vmlx_matches)

    if seconds:
        vmlx_decode_tps = round(tokens / seconds, 2)

# Generic backend tok/s readings, useful especially for LM Studio logs.
backend_tps = [
    float(x)
    for x in re.findall(
        r"([0-9]+(?:\.[0-9]+)?)\s*(?:tok/s|tokens/s)",
        backend_log,
        flags=re.I,
    )
]

(run / "answer.md").write_text(answer + "\n")

summary = {
    "backend": backend,
    "prompt": prompt,
    "load_seconds": load_seconds,
    "generation_wall_seconds": generation_seconds,
    "prompt_tokens": prompt_tokens,
    "completion_tokens": completion_tokens,
    "total_tokens": total_tokens,
    "wall_completion_tokens_per_second": wall_decode_tps,
    "vmlx_reported_decode_tps": vmlx_decode_tps,
    "backend_reported_tps_candidates": backend_tps,
    "finish_reason": choice.get("finish_reason"),
    "answer_chars": len(answer),
}

(run / "summary.json").write_text(
    json.dumps(summary, indent=2) + "\n"
)

print()
print("========== BACKEND BENCH SUMMARY ==========")
print(json.dumps(summary, indent=2))
print("===========================================")
PY

cleanup
trap - EXIT INT TERM

echo
echo "Run saved to:"
echo "  $RUN_DIR"
