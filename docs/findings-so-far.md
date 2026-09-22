# Benchmark Findings So Far

This document summarizes the benchmark results collected so far using
Qwen3-Coder-Next MLX 6-bit on an Apple M4 Max with 128 GB unified memory.

The project is intended to answer two separate questions:

1. Which local inference backend performs best for the same model?
2. Which vMLX runtime configuration is best for a single-user local coding workload?

The benchmark currently uses three prompt types:

- `architecture`
- `coding`
- `json`

Each reported comparison uses three repetitions per prompt/backend or prompt/profile pair and reports medians.

---

## 1. vMLX vs LM Studio

### Configuration

Both backends used the same Qwen3-Coder-Next MLX 6-bit model and equivalent generation settings.

The initial vMLX baseline used the direct single-request engine:

```text
--no-continuous-batching
```

This profile is now called:

```text
vmlx-simple
```

### Median generation throughput

| Prompt | vMLX | LM Studio | Difference |
|---|---:|---:|---:|
| Architecture | 59.81 tok/s | 53.75 tok/s | vMLX +11.3% |
| Coding | 48.57 tok/s | 42.11 tok/s | vMLX +15.3% |
| JSON | 40.96 tok/s | 36.90 tok/s | vMLX +11.0% |

Across these workloads, vMLX produced approximately 11–15% higher median generation throughput than LM Studio.

Cold model loading was also generally faster with vMLX, particularly in the coding and JSON runs, although load time showed more run-to-run variability than generation speed.

### Quality checks

| Prompt | vMLX | LM Studio |
|---|---:|---:|
| Coding | 73.3% | 73.3% |
| Architecture | 94.4% | 88.9% |
| JSON | 100% | 100% |

These are deterministic task-compliance checks rather than general intelligence scores.

The benchmark did not show evidence of a meaningful output-quality disadvantage from using vMLX.

The small architecture difference should not be treated as statistically significant given the sample size.

### Finding

For this model and hardware, vMLX is currently the better-performing backend for the tested local single-user workloads.

---

## 2. vMLX Simple vs Continuous Batching

The next experiment tested whether vMLX continuous batching improves single-request performance.

### Simple profile

```text
--no-continuous-batching
```

### Continuous profile

```text
--continuous-batching
--max-num-seqs 1
--disable-prefix-cache
--no-paged-cache
--disable-block-disk-cache
```

The cache layers were deliberately disabled so that the experiment measured the effect of the continuous scheduling engine rather than cache reuse.

### Median results

| Prompt | Profile | Load | Generation | Wall tok/s | Decode tok/s |
|---|---|---:|---:|---:|---:|
| Architecture | vmlx-simple | 15.489 s | 39.966 s | 60.630 | 60.710 |
| Architecture | vmlx-continuous | 15.567 s | 48.245 s | 54.050 | 54.110 |
| Coding | vmlx-simple | 15.538 s | 18.243 s | 50.200 | 50.340 |
| Coding | vmlx-continuous | 14.479 s | 22.082 s | 43.130 | 43.210 |
| JSON | vmlx-simple | 14.547 s | 19.073 s | 43.170 | 43.260 |
| JSON | vmlx-continuous | 14.506 s | 18.333 s | 43.350 | 43.460 |

### Relative decode performance

| Prompt | Result |
|---|---:|
| Architecture | simple +12.2% |
| Coding | simple +16.5% |
| JSON | continuous +0.5% |
| Cross-task median | simple +12.2% |

Load times were effectively similar.

The meaningful difference appeared during decoding.

### Finding

For a single-user, single-request workload, the direct vMLX engine is the better default.

Continuous batching with cache reuse disabled produced approximately 12% lower median decode throughput across the three workloads.

The likely interpretation is that continuous batching adds scheduling machinery intended for concurrent workloads, while this benchmark deliberately provides neither concurrency nor cache reuse from which that machinery can benefit.

The JSON workload was effectively tied, suggesting the continuous engine is not universally slower, but there is currently no performance reason to prefer it for this benchmark's single-request use case.

---

## Current Recommended Profile

For Qwen3-Coder-Next MLX 6-bit on this machine:

```text
Backend: vMLX
Mode: direct / simple
Continuous batching: disabled
```

In other words:

```text
vmlx-simple
```

is currently the benchmark's preferred single-user baseline.

---

## What These Results Do Not Establish

These results should not be generalized to:

- multi-user inference
- concurrent agent requests
- heavily repeated system prompts
- long multi-turn conversations
- workloads benefiting from prefix reuse
- other Apple Silicon generations
- other models or quantizations

Continuous batching may become advantageous once concurrency or caching is introduced.

---

## Next Experiments

The current baseline is now sufficiently established that further work should test additional optimization mechanisms individually.

### 1. Prompt Lookup Decoding / PLD

Test whether speculative or prompt-assisted decoding can improve generation throughput while keeping the simple single-request engine.

This is particularly relevant to coding workloads because generated code often contains repeated or predictable token sequences.

### 2. Continuous batching with cache reuse

Separately test continuous mode with:

- prefix cache
- paged cache
- repeated-prefix workloads

This answers a different question from the current experiment:

> Can cache reuse make the continuous engine worthwhile for realistic multi-turn or agent workflows?

### 3. Larger mixed-precision models

Use the same benchmark harness to evaluate larger models and JANG mixed-precision quantization profiles.

The objective will shift from pure backend performance toward the trade-off between:

- reasoning quality
- coding quality
- memory use
- generation speed

on a 128 GB Apple Silicon machine.

---

## Current Overall Result

So far, the experiments support the following practical configuration for local single-user coding and reasoning:

```text
Qwen3-Coder-Next MLX 6-bit
        +
vMLX
        +
direct/simple inference
```

Compared with LM Studio, vMLX was approximately 11–15% faster in median generation throughput.

Within vMLX, the direct engine was approximately 12% faster at median decode throughput than continuous batching when cache reuse was disabled.

This configuration therefore remains the reference baseline for subsequent optimization experiments.
