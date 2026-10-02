# Baseline Results

## Hardware

Apple Silicon Mac:
- M4 Max
- 128 GB unified memory

## Model

Qwen3-Coder-Next MLX 6-bit

## Backends

- vMLX
- LM Studio

Both backends were tested with the same model family, prompts, sampling
configuration, and output token limits.

Each benchmark task was run three times per backend.

## Median performance

| Task | vMLX tok/s | LM Studio tok/s | vMLX advantage |
|---|---:|---:|---:|
| Architecture | 59.81 | 53.75 | +11.3% |
| Coding | 48.57 | 42.11 | +15.3% |
| JSON | 40.96 | 36.90 | +11.0% |

## Quality checks

| Task | vMLX | LM Studio |
|---|---:|---:|
| Coding | 73.3% | 73.3% |
| Architecture completeness | 94.4% | 88.9% |
| JSON compliance | 100% | 100% |

The quality scorer is primarily a **structural/compliance test** and should
not be interpreted as a general model intelligence benchmark.

**Important:** Coding, JSON, and architecture quality scores are **task-specific checks**. They are not a common cross-task quality scale and should not be compared directly across prompt types.

The architecture difference is based on a small sample (n=3) and should not
be treated as statistically meaningful.

**Limitations of architecture scoring:**
- Relies on keyword/checklist-based detection
- May miss nuanced architectural issues that don't use expected terminology
- May flag superficial mentions without deep understanding
- Scores are prompt-specific, not absolute quality measures

## Initial conclusion

On this benchmark, vMLX delivered approximately 11–15% higher median
generation throughput than LM Studio while showing no demonstrated loss
of answer quality.

Cold model loading was also generally faster with vMLX, although load
time showed more run-to-run variation than generation throughput.

**Note on methodology:** All benchmark results use approximately n=3 repetitions per condition and should be treated as **preliminary/exploratory** rather than statistically conclusive. Dispersion measures (e.g., IQR) are provided where the underlying data supports them.
