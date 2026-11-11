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
- **Scrubbing:** has no visible effect.
  - With warm-up, C vs E: std 92 vs 89.
  - Without warm-up, B vs D: std 147 vs 147.
  - The mean differences between these pairs (about 30 cycles) are within the normal run-to-run variation of
    this benchmark.
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
