#!/bin/bash
# Round 2: WARMUP_HOPS x SAMPLE_SIZE sweep on config E (current code, scrub on). Builds 25 binaries, then runs
# each 10 times. Output: $RESULTS/W<hops>_S<samples>/run<i>.txt (RESULTS defaults to results/round2).
# Other GPUs: e.g. GPU=0 GPU_TARGET_ARCH=sm_90 RESULTS=$PWD/results/gh200/round2 scripts/round2.sh
set -euo pipefail
EXP=$(cd "$(dirname "$0")/.." && pwd)
HOPS=(0 128 512 2048 8192); SIZES=(256 512 1024 2048 4096)
specs=(); cfgs=()
for h in "${HOPS[@]}"; do for n in "${SIZES[@]}"; do
    specs+=("W${h}_S${n}=MM_WARMUP_HOPS=$h;MM_SAMPLE_SIZE=$n"); cfgs+=("W${h}_S${n}")
done; done
"$EXP/scripts/build_configs.sh" "${specs[@]}"
RESULTS=${RESULTS:-$EXP/results/round2} "$EXP/scripts/run.sh" 10 "${GPU:-1}" "${cfgs[@]}"
