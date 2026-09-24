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

## PLD experiment — Qwen3-Coder-Next / vMLX

**Date:** 2026-09-23

### Question

Can vMLX Prompt Lookup Decoding (PLD) improve single-request coding throughput for Qwen3-Coder-Next MLX 6-bit?

### Setup

The baseline continuous-batching profile used:

```text
--continuous-batching
--max-num-seqs 1
--disable-prefix-cache
--no-paged-cache
--disable-block-disk-cache
```

The PLD profile was identical except for:

```text
--enable-pld
```

PLD did not activate meaningfully with the vMLX Simple engine, so the controlled PLD test used continuous batching.

### Continuous baseline

A prior `vmlx-continuous` coding run produced:

| Metric | Result |
|---|---:|
| Completion tokens | 1,014 |
| Generation wall time | 22.082 s |
| Wall throughput | 45.92 tok/s |
| vMLX reported decode | 46.24 tok/s |

### PLD sanity run 1

| Metric | Result |
|---|---:|
| Completion tokens | 832 |
| Generation wall time | 21.363 s |
| Wall throughput | 38.95 tok/s |
| vMLX reported decode | 39.02 tok/s |

PLD startup was confirmed:

```text
[PLD] enabled — K=2 (hybrid model), d0 pre-check active, auto-tune on
```

The runtime then disabled speculative execution almost immediately:

```text
[PLD:3b1f] auto-tune — disabled (0 rounds in 1 tokens, d0 pre-check filtered all)
```

Prompt-lookup diagnostics:

| Tokens observed | Coverage | hit@1 | Mean depth | Theoretical speedup |
|---:|---:|---:|---:|---:|
| 200 | 13.0% | 30.8% | 1.62 | 1.07x |
| 400 | 12.8% | 31.4% | 1.75 | 1.08x |
| 600 | 16.3% | 25.5% | 1.76 | 1.08x |
| 800 | 19.8% | 36.1% | 2.05 | 1.17x |

### PLD sanity run 2

A second independent coding run reproduced the same behavior.

| Metric | Result |
|---|---:|
| Completion tokens | 794 |
| Generation wall time | 19.718 s |
| Wall throughput | 40.27 tok/s |
| vMLX reported decode | 40.37 tok/s |
| PLD enabled | Yes |
| PLD auto-tuner disabled | Yes |

Prompt-lookup diagnostics:

| Tokens observed | Coverage | hit@1 | Mean depth | Theoretical speedup |
|---:|---:|---:|---:|---:|
| 200 | 9.5% | 21.1% | 2.00 | 1.04x |
| 400 | 10.8% | 20.9% | 1.67 | 1.04x |
| 600 | 13.7% | 37.8% | 2.68 | 1.16x |

No effective-tokens-per-pass result was emitted because PLD's auto-tuner disabled speculative execution before meaningful speculative rounds were performed.

### Finding

PLD is not useful for the current Qwen3-Coder-Next coding workload.

Both PLD trials caused the runtime's own cost gate to disable speculative execution. Prompt lookup found some reusable structure, but coverage was only about 10–20%, and the theoretical opportunity was insufficient for PLD to remain enabled.

Observed decode rates were:

```text
vmlx-continuous baseline     46.24 tok/s
vmlx-continuous-pld #1      39.02 tok/s
vmlx-continuous-pld #2      40.37 tok/s
```

Because PLD disabled itself, these figures should not be interpreted as proof that active PLD inherently causes a 13–16% slowdown. They show that PLD does not activate beneficially for this workload and provides no demonstrated performance benefit.

A full 18-run PLD matrix was therefore not justified.

### Decision

For the current single-user coding workload:

1. Keep `vmlx-simple` as the preferred performance baseline.
2. Retain `vmlx-continuous` for experiments requiring continuous batching, caching, concurrency, or hybrid-model functionality.
3. Do not enable PLD by default for Qwen3-Coder-Next.
4. Revisit PLD only for workloads with substantially more repetitive or structured output, or with a different model.

The benchmark harness now records:

- PLD activation
- PLD auto-tuner state
- prompt-lookup coverage
- hit@1
- mean lookup depth
- theoretical speedup
- effective tokens/pass when emitted by vMLX

Qwen3.5-122B-A10B-JANG_2S
- bundle loads
- first forward pass fails with gather_qmm shape mismatch
- issue filed: jjang-ai/vmlx#280

Nemotron-3-Super-120B-A12B-JANG_4M
- vmlx 1.6.64
- 120.8B parameters
- 62.6 GB JANG 4.1-bit bundle
- mlx-lm MoEGate quantization bug blocked loading
- upstream no-op MoEGate.to_quantized() patch applied locally
- server then started successfully
- first 128-token generation succeeded
- native MTP disabled for smoke test


### Nemotron 120B tool-calling smoke test

`JANG/Nemotron-3-Super-120B-A12B-JANG_4M` successfully emitted a valid OpenAI-style function call under vMLX 1.6.64 using:

- `--enable-auto-tool-choice`
- `--tool-call-parser nemotron`
- native MTP disabled
- thinking disabled

Prompt requested current Amsterdam weather and explicitly instructed the model to use the available tool rather than guess.

Result:

- `finish_reason: tool_calls`
- `content: null`
- tool: `get_weather`
- arguments: `{"city":"Amsterdam"}`

This confirms the model is viable for further OpenCode / reviewer-agent testing, not just plain text generation.
