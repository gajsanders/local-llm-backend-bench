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

- Cold model load time
- Generation wall time
- Completion throughput
- Prompt and completion token counts
- Output length
- Strict JSON compliance
- Simple deterministic task-quality checks

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

The quality checks are deliberately simple and deterministic. They should be treated as task-compliance checks, not as a general model intelligence benchmark.

The architecture difference is based on a small sample and should not be treated as statistically meaningful.

### Initial conclusion

On this benchmark, vMLX delivered approximately **11–15% higher median generation throughput** than LM Studio with **no demonstrated loss of output quality**.

Cold loading was also generally faster with vMLX, although load time showed more run-to-run variation than generation throughput.

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
