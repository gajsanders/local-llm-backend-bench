# Local LLM Backend Bench

A small reproducible benchmark for comparing local LLM inference backends on Apple Silicon.

The goal is to separate **model quality** from **runtime performance** by running the same model against the same prompts, sampling settings, and deterministic quality checks across different inference backends.

## Current backends

- vMLX
- LM Studio

## Current model

Qwen3-Coder-Next MLX 6-bit

The same local model weights are used by both backends, but the runtime identifiers differ:

- LM Studio model key: `qwen/qwen3-coder-next`
- Default vMLX model directory:
  `~/.lmstudio/models/lmstudio-community/Qwen3-Coder-Next-MLX-6bit`

The vMLX model path can be overridden with `MODEL_DIR`.

## Hardware used for the initial benchmark

- Apple M4 Max
- 128 GB unified memory
- macOS

## What the benchmark measures

- **Cold model load time**: Time from starting the backend server to first token generation (no warm-up)
- **Generation wall time**: Time for a single inference request once the model is loaded
- Completion throughput (tokens per second)
- Prompt and completion token counts
- Output length
- Strict JSON compliance
- Simple deterministic task-quality checks

**Important:** The benchmark does NOT perform warm-up inference before cold-load measurements, as that would change the quantity being measured. Cold-load timing measures actual startup latency; generation timing measures inference throughput once warmed up.

## Benchmark tasks

The current suite contains three workloads:

### `coding`

Python correctness and code-review task covering:

- bugs
- edge cases
- complexity
- improved implementation
- focused tests

### `architecture`

Architecture reasoning task covering:

- architectural problems
- target layering
- shared vs model-specific abstractions
- package structure
- migration strategy
- areas that should not be generalized yet

### `json`

Strict structured-output task covering:

- JSON validity
- exact top-level structure
- bug identification
- exact test count
- corrected replacement code

## Initial baseline

Qwen3-Coder-Next MLX 6-bit was benchmarked with:

- 3 prompts
- 2 backends
- 3 repetitions per prompt/backend pair

Total:

```text
3 prompts × 2 backends × 3 repetitions = 18 runs
```

**Note:** These results use approximately n=3 repetitions per condition and should be treated as **preliminary/exploratory** rather than statistically conclusive. Claims of statistical significance are not supported without proper inferential testing, and n is currently too small for such tests. Results should be interpreted as early indicators rather than definitive conclusions.

### Median generation throughput

| Task | vMLX | LM Studio | vMLX advantage |
|---|---:|---:|---:|
| Architecture | 59.81 tok/s | 53.75 tok/s | +11.3% |
| Coding | 48.57 tok/s | 42.11 tok/s | +15.3% |
| JSON | 40.96 tok/s | 36.90 tok/s | +11.0% |

### Quality checks

| Task | vMLX | LM Studio |
|---|---:|---:|
| Coding | 73.3% | 73.3% |
| Architecture completeness | 94.4% | 88.9% |
| JSON compliance | 100% | 100% |

The quality checks are deliberately simple and deterministic. They should be treated as **task-compliance checks**, not as a general model intelligence benchmark.

**Important:** Coding, JSON, and architecture quality scores are task-specific checks. They are not a common cross-task quality scale and should not be compared directly across prompt types.

The architecture difference is based on a small sample and should not be treated as statistically meaningful.

### Initial conclusion

On this benchmark, vMLX delivered approximately **11–15% higher median generation throughput** than LM Studio with **no demonstrated loss of output quality**.

Cold loading was also generally faster with vMLX, although load time showed more run-to-run variation than generation throughput.

**Note on methodology:** This benchmark measures cold-load startup time and single-request generation performance. Results are preliminary (n=3) and exploratory rather than statistically conclusive.

## Current Findings

The experiments completed so far indicate that **vMLX using its direct/simple
single-request engine is the current best baseline** for Qwen3-Coder-Next MLX
6-bit on the tested M4 Max 128 GB system.

- vMLX was approximately **11–15% faster than LM Studio** across the initial
  architecture, coding, and JSON workloads.
- Within vMLX, the direct engine was approximately **12% faster at median
  decode throughput** than continuous batching when cache reuse was disabled.
- No meaningful output-quality disadvantage was observed for vMLX in the
  current deterministic task checks.

**Note on methodology:** All benchmark results use approximately n=3 repetitions per condition and should be treated as **preliminary/exploratory** rather than statistically conclusive. Dispersion measures (e.g., IQR) are provided where the underlying data supports them.

See [Benchmark Findings So Far](docs/findings-so-far.md) for the full results
and methodology.

## Requirements

- Apple Silicon Mac
- Python 3
- `curl`
- `lsof`
- vMLX
- LM Studio
- LM Studio CLI (`lms`)

LM Studio commonly exposes the CLI at:

```text
~/.lmstudio/bin/lms
```

The benchmark runner adds that directory to `PATH` automatically if it exists.

## Repository structure

```text
backend-bench/
├── prompts/
│   ├── architecture.txt
│   ├── coding.txt
│   └── json.txt
├── results/
│   └── .gitkeep
└── scripts/
    ├── bench.sh
    ├── compare.py
    ├── make-current-batch.py
    ├── run-matrix.sh
    └── score-quality.py
docs/
└── baseline-results.md
```

## Running one benchmark

Run vMLX:

```bash
./backend-bench/scripts/bench.sh vmlx coding
```

Run LM Studio:

```bash
./backend-bench/scripts/bench.sh lmstudio coding
```

Available prompt names:

```text
coding
architecture
json
```

## Overriding the vMLX model path

If your model is stored elsewhere:

```bash
MODEL_DIR="/path/to/Qwen3-Coder-Next-MLX-6bit" \
./backend-bench/scripts/bench.sh vmlx coding
```

## Overriding the LM Studio model key

If your LM Studio model key differs:

```bash
LM_MODEL_KEY="your/model-key" \
./backend-bench/scripts/bench.sh lmstudio coding
```

## Running the full matrix

```bash
./backend-bench/scripts/run-matrix.sh
```

The default matrix runs:

```text
3 prompts × 2 backends × 3 repetitions
```

## Building a comparison batch

After the matrix completes:

```bash
python3 backend-bench/scripts/make-current-batch.py
```

Then compare performance:

```bash
python3 backend-bench/scripts/compare.py
```

And run deterministic quality checks:

```bash
python3 backend-bench/scripts/score-quality.py
```

## Benchmark philosophy

The benchmark intentionally keeps inference-engine comparison separate from:

- agent frameworks
- MCP servers
- tool calling
- repository navigation
- orchestration layers

Those introduce additional compatibility and prompting variables that can obscure raw backend performance.

## Methodology notes

### Small-sample limitations

Results are based on approximately n=3 repetitions per condition. These should be treated as **preliminary/exploratory** rather than statistically conclusive. Claims of statistical significance are not supported without proper inferential testing.

### Quality metrics

Quality scores (coding, JSON, architecture) are **task-specific compliance checks**, not a common cross-task quality scale. They should not be compared directly across prompt types.

Architecture scoring relies on keyword/checklist-based detection and has known limitations:
- May miss nuanced architectural issues
- May flag superficial mentions without deep understanding
- Scores are prompt-specific, not absolute quality measures

### vMLX startup semantics

The benchmark distinguishes between:
- **Cold-load timing**: Model loading from disk to first token generation
- **Warm generation timing**: Subsequent inference once the model is loaded

No warm-up inference is performed before cold-load measurements, as that would change what is being measured.

The readiness check confirms the expected model ID is exposed via the `/v1/models` endpoint.

### Timing semantics

All reported load times are **cold-load measurements** (no warm-up). Generation times are measured for single inference requests after the model is loaded. This distinction is important because:
- Cold-load time includes model disk I/O, memory allocation, and initial compilation
- Generation time measures inference throughput once the model is in memory

Results should not be compared with benchmarks that perform warm-up runs, as those measure different quantities.

## Planned experiments

Future work includes:

- vMLX continuous batching
- vMLX cache configurations
- speculative decoding / PLD
- larger mixed-precision models
- JANG quantization profiles
- additional coding and reasoning workloads
- larger-model reasoning comparisons on 128 GB Apple Silicon

## Caveats

This is a practical local benchmark, not a comprehensive model evaluation.

Results can vary with:

- Apple Silicon generation
- available unified memory
- model quantization
- backend version
- sampling settings
- thermal state
- context size
- workload

Quality checks are primarily structural and deterministic rather than LLM-as-judge evaluation.

## License

MIT
