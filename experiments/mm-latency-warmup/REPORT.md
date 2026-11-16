# Main-memory latency: effect of warm-up and cache scrubbing (MI210, milan1)

One AMD Instinct MI210 (gfx90a, GPU 1 on milan1), ROCm 7.2.4. 1 GiB working set, 1 KiB stride, 2048 timed loads.

## Configurations

| Cfg | Description | Source |
|---|---|---|
| A | original (`32ebe6b^`)  | `configs/A/mainMemoryLatency.cpp` |
| B | current without warm-up and scrubbing  | `configs/B/mainMemoryLatency.cpp` |
| C | current without scrubbing  | `configs/C/mainMemoryLatency.cpp` |
| D | current without warm-up  | `configs/D/mainMemoryLatency.cpp` |
| E | current (`my-pr45-improvements` HEAD) | `configs/E/mainMemoryLatency.cpp` |

## Results

Each configuration ran 10 times, as separate processes. The configs were shuffled within each round, with a 2 s
pause before every run.

**Plots** (`results/plots/<cfg>.png`): run 1 of each configuration, sample index vs. latency in cycles.

**Table** (`results/summary.md`): mean ± standard deviation over all samples of all 10 runs.

| cfg | description | mean ± std (cycles) |
|---|---|---|
| A | original | 756 ± 182 |
| B | current without warm-up and scrub | 724 ± 147 |
| C | current without scrub | 691 ± 92 |
| D | current without warm-up | 749 ± 147 |
| E | current (warm-up + scrub) | 720 ± 89 |

## Does warm-up and/or scrubbing remove the initial high latency?

**The warm-up removes it. Scrubbing does not.**

- **Without warm-up (A, B, D):** every run starts with the high-latency region.
  - The first 100 samples average about 1060–1100 cycles, versus about 710–740 for the rest (10/10 runs each).
  - It fades out within a few hundred samples.
  - D, with scrub but no warm-up, looks the same as B, with neither.
- **With warm-up (C, E):** no run has it (0/10 each). The first 100 samples equal the rest (689 vs 691, and
  720 vs 720 cycles).
- **Scrubbing:** does not remove the initial high latency.
  - With warm-up, C vs E: std 92 vs 89.
  - Without warm-up, B vs D: std 147 vs 147.
  - The mean differences between these pairs (about 30 cycles) were first put down to run-to-run variation. That
    was an untested assumption: with 40 runs per config, scrub makes results about 11–15 cycles slower. See
    "Cache scrub: what it does and whether it matters" below.
- **The warm-up lowers the std** (147 → 89–92 on the current code) because the slow start-up samples are no
  longer recorded.

## Files

| Path | What |
|---|---|
| `configs/<cfg>/mainMemoryLatency.cpp` | source of each configuration |
| `results/<cfg>/run<i>.txt` | raw data: one latency (cycles) per line, one file per run |
| `results/plots/<cfg>.png` | plot of run 1 |
| `results/summary.md` | the table above |
| `scripts/build_configs.sh` | builds `bins/mt4g-<cfg>` (the config list is at the top of the script) |
| `scripts/run.sh` | `scripts/run.sh 10 <gpu> A B C D E` |
| `scripts/analyze.py` | makes the plots and the table |
| `scripts/scrub_check.sh` | L2 counters with/without scrub and the two L2 tests in `scrub-check/` (AMD only) |
| `scripts/analyze_scrub40.py` | 40-run scrub comparison table from `results/scrub40/` |

To build the configurations, `src/benchmarks/latency/mainMemoryLatency.cpp` on this branch has three compile-time
switches: `MM_ORIGINAL`, `MM_WARMUP_HOPS` and `MM_SCRUB`. `CMakeLists.txt` passes them in through
`MM_EXP_DEFS`. With no switches set, the file behaves exactly like HEAD.

`src/main.cpp` has two changes:
- `MT4G_EXP_MM_LATENCY_ONLY=1` stops the program after the latency measurement.
- A compile fix: `my-pr45-improvements` HEAD does not build, because `main.cpp` still calls the removed
  `runOptimalSearch` and `measureL1Read/WriteBandwidth`.

These three files exist only for this study and should not be merged into the benchmark.

## Round 2: WARMUP_HOPS × SAMPLE_SIZE sweep (config E)

Config E (current code, scrub on) with WARMUP_HOPS ∈ {0, 128, 512, 2048, 8192} and SAMPLE_SIZE ∈
{256, 512, 1024, 2048, 4096}: 25 configurations, 10 runs each, shuffled within each round.

- **Plots:** `results/round2/plots/W<hops>_S<samples>.png` shows run 1 of each configuration;
  `results/round2/plots/grid.png` shows all 25 side by side.
- **Raw data:** `results/round2/W<hops>_S<samples>/run<i>.txt`.
- **Script:** `scripts/round2.sh` builds and runs the sweep; `scripts/analyze_round2.py` makes the plots and
  the table.

**Table** (`results/round2/summary.md`): mean ± std in cycles. Both are computed per run, then averaged over the
10 runs.

| SAMPLE_SIZE \ WARMUP_HOPS | 0 | 128 | 512 | 2048 | 8192 |
|---|---|---|---|---|---|
| **256** | 893 ± 304 | 730 ± 124 | 717 ± 81 | 713 ± 86 | 714 ± 84 |
| **512** | 790 ± 240 | 735 ± 117 | 722 ± 89 | 714 ± 88 | 717 ± 86 |
| **1024** | 759 ± 185 | 711 ± 100 | 691 ± 89 | 703 ± 85 | 719 ± 87 |
| **2048** | 737 ± 144 | 729 ± 90 | 711 ± 85 | 698 ± 91 | 711 ± 82 |
| **4096** | 727 ± 121 | 729 ± 92 | 710 ± 85 | 713 ± 87 | 729 ± 86 |

### Observations

**WARMUP_HOPS = 0:**

- The first ~100–300 samples are slow (first 100 samples about 1.4–1.5× the rest).
- Their share of the trace shrinks as SAMPLE_SIZE grows, so the measured mean and std fall:
  893 ± 304 at 256 samples, down to 727 ± 121 at 4096.
- So without warm-up the reported latency depends on how many samples are taken, which a latency benchmark
  should not.

**WARMUP_HOPS = 128 is not enough.**

- The transient is mostly gone: no run exceeds 1.15× in the first 100 samples.
- A remainder is still visible: the first 100 samples are 4–7 % slower than the rest.
- The std stays elevated at small SAMPLE_SIZE: 124 at 256 samples and 117 at 512, versus about 85 otherwise.

**WARMUP_HOPS ≥ 512: the transient is gone, and neither parameter has a measurable effect any more.**

- All 15 configurations measure mean 691–729 and std 81–91 cycles.
- That spread is within the normal run-to-run variation
- There is no trend with WARMUP_HOPS or with SAMPLE_SIZE.
## Running on another GPU (e.g. NVIDIA)

The study branch builds for NVIDIA through mt4g's normal `sm_` path, which needs `hipcc` for the nvidia platform
(HIP headers over CUDA, forwarding to `nvcc`), plus `nlohmann_json` and `cxxopts`.
Put the results in their own directory so the MI210 data is not overwritten:

```bash
cd experiments/mm-latency-warmup
export GPU_TARGET_ARCH=sm_90                                   # e.g. sm_80 for A100, sm_90 for H100/GH200
export CMAKE_ARGS="-DCMAKE_CXX_COMPILER=$HIP_PATH/bin/hipcc -DCMAKE_PREFIX_PATH=<deps> -DCUDAToolkit_ROOT=/usr/local/cuda"
# Round 1
scripts/build_configs.sh A="MM_ORIGINAL=1;MM_WARMUP_HOPS=0" B="MM_WARMUP_HOPS=0;MM_SCRUB=0" C="MM_SCRUB=0" D="MM_WARMUP_HOPS=0" E=""
RESULTS=$PWD/results/<gpu> scripts/run.sh 10 <gpu-id> A B C D E
python3 scripts/analyze.py results/<gpu> <GPU-name>
# Round 2
GPU=<gpu-id> RESULTS=$PWD/results/<gpu>/round2 scripts/round2.sh
python3 scripts/analyze_round2.py results/<gpu>/round2 <GPU-name>
```

- **Timer:** on NVIDIA, `__timer()` reads the 32-bit SM `%clock`, not `s_memtime`, so cycle counts can only be
  compared within one GPU.
- **SAMPLE_SIZE:** stays within the default 48 KiB of static shared memory up to 6144 (the largest value used here
  is 4096).
- **Plots:** for any GPU other than the MI210, the y-axis is scaled automatically.

## Cache scrub: what it does and whether it matters (MI210)

### The caches involved

| Level | Size | Line size | Shared by |
|---|---|---|---|
| vL1 (vector L1) | 16 KiB | 64 B | one compute unit (CU) |
| L2 | 8 MiB | 128 B (measured by mt4g) | all 104 CUs |
| Main memory (HBM) | 64 GiB | – | – |

The MI210 has no cache between L2 and main memory (the MI300A has a 256 MB Infinity Cache there). The measuring
load skips vL1, so the only cache that could serve it is L2.

### What the scrub kernel does

Before the measuring kernel, the launcher runs:

1. **Init kernel:** 3,328 blocks × 256 threads copy the chain from `d_initArray` (a 1 GiB copy uploaded from the
   host) into `d_pChaseArray` (the array that is measured).
2. **Scrub kernel:** the same grid reads `d_initArray`, **not** the measured array. Each thread reads one 4-byte word
   every 64 bytes (`SCRUB_STRIDE_BYTES`) and XORs the values into a small output array, so the compiler cannot
   delete the loads.
3. `d_initArray` is freed, then the measuring kernel runs on one thread.

The idea: after the init kernel, L2 holds the last ~8 MiB touched, possibly including parts of the measured array.
A timed load that hit such a line would take about 300 cycles instead of about 700. Reading 1 GiB of other data
(128 × the L2 size) should push those lines out. The code comment itself says it "is not a guaranteed cache flush".

The scrub does not use the line size mt4g measures. With 64 B steps and 128 B L2 lines, every line is read twice:
the counters below show 16.8 M L2 requests but only 8.4 M misses, one per 128 B line. That only doubles the work.
For pushing data out, the step size barely matters: what matters is the amount of different data read. Even a
1 KiB step over 1 GiB would bring 128 MiB of lines into L2, 16 × its size.

### Does it remove anything? (`results/scrub-check/`, `scripts/scrub_check.sh`)

**On the MI210 it has nothing to remove: L2 does not keep data from one kernel to the next.**

- **The measuring load does hit L2 within one kernel** (`scrub-check/same_kernel_l2.cpp`). mt4g's
  `__forceBypassAllCacheReads` (`flat_load_dword glc slc`) says it bypasses L1 and L2, but a line loaded earlier in
  the same kernel comes back in about 290 cycles instead of about 570, and counts as an L2 hit. So it skips vL1 only.
- **Data cached by an earlier kernel is gone** (`scrub-check/cross_kernel_l2.cpp`). Lines loaded by one kernel
  take the main-memory latency (about 560–580 cycles) in the next kernel, even with a load that is allowed to hit L2.
- **The measuring kernel's L2 counters are the same with and without scrub** (rocprofv3, 3 runs each, each with a
  different random chain):

| | L2 requests | L2 hits | L2 misses | Main-memory reads |
|---|---|---|---|---|
| C (no scrub) | 4,701–4,703 | 459 | 4,242–4,244 | 4,188–4,190 |
| E (scrub) | 4,701–4,702 | 459 | 4,242–4,243 | 4,188–4,189 |

  The kernel does 4,096 chain loads (2,048 warm-up + 2,048 timed), and there are at least that many main-memory
  reads. The 459 hits are the same in every run regardless of the chain, so they come from the kernel's other
  traffic (result writes, code and argument fetches), not from chain loads.
- **Even if L2 kept data, the effect would be tiny.** Each chain entry is visited once, and at most 8 MiB of the
  1 GiB array fits in L2, so fewer than 1% of the loads could hit.

### Does it change the result? (`results/scrub40/`, `scripts/analyze_scrub40.py`)

A further 40 runs each of B, C, D and E (`scripts/run.sh 40 1 B C D E`, shuffled per round). Each run settles at
one of two levels, about 672 or about 732 cycles; a run counts as "high" when its median is above 700.

| cfg | scrub | warm-up | runs | mean of run means | sd of run means | runs at high level |
|---|---|---|---|---|---|---|
| B | off | off | 40 | 721 | 30 | 14/40 |
| D | on | off | 40 | 732 | 28 | 23/40 |
| C | off | on | 40 | 704 | 31 | 17/40 |
| E | on | on | 40 | 719 | 24 | 30/40 |

| comparison | difference (scrub - no scrub) | permutation p |
|---|---|---|
| E - C (warm-up on) | +15.0 cycles | 0.018 |
| D - B (warm-up off) | +11.4 cycles | 0.085 |

- Scrub makes results about 11–15 cycles (about 2%) slower, by making more runs land at the high level.
- It is not caused by what is in L2, since the counters are identical. The cause is unknown; physical memory
  placement or GPU state left by the heavy 1 GiB kernel are possible explanations, neither tested.
- With 10 runs per config the smallest reliably detectable difference was about 34 cycles, which is why round 1
  could not tell this apart from noise.

### Conclusions

- On the MI210 the scrub does not remove anything the measuring kernel could use; every chain load goes to main
  memory with or without it. It does shift the measured latency up by about 2%.
- It may still matter on the MI300A, whose Infinity Cache sits in front of main memory and probably is not
  cleared between kernels. That has not been tested, and CDNA3 uses a different load (`sc0 sc1 nt`).
