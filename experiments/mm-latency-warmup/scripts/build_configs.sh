#!/bin/bash
# Build one mt4g binary per configuration into experiments/mm-latency-warmup/bins/mt4g-<name>.
# Usage: build_configs.sh NAME="DEFS" ...   e.g. build_configs.sh A="MM_ORIGINAL=1;MM_WARMUP_HOPS=0"
# Configs of this study: A="MM_ORIGINAL=1;MM_WARMUP_HOPS=0" B="MM_WARMUP_HOPS=0;MM_SCRUB=0" C="MM_SCRUB=0" D="MM_WARMUP_HOPS=0" E=""
# DEFS are passed as MM_EXP_DEFS (CMake list, ';'-separated); empty DEFS == HEAD behaviour.
# GPU_TARGET_ARCH selects the GPU (default gfx90a = MI210). For NVIDIA, e.g. GPU_TARGET_ARCH=sm_90: needs hipcc
# (HIP with the nvidia platform) on PATH or in CMAKE_ARGS as -DCMAKE_CXX_COMPILER=...; extra configure flags
# (CMAKE_PREFIX_PATH, CUDAToolkit_ROOT, ...) go in CMAKE_ARGS.
set -euo pipefail
EXP=$(cd "$(dirname "$0")/.." && pwd)        # experiments/mm-latency-warmup
ROOT=$(cd "$EXP/../.." && pwd)                 # repository root
source "$EXP/scripts/env.sh"
B=$EXP/build; mkdir -p "$EXP/bins"
ARCH=${GPU_TARGET_ARCH:-gfx90a}
if [[ $ARCH == gfx* ]]; then
    ARCH_ARGS=(-DCMAKE_CXX_COMPILER=/opt/rocm/llvm/bin/amdclang++ "-DCMAKE_PREFIX_PATH=$HOME/opt/mt4g-deps;/opt/rocm")
else
    ARCH_ARGS=()
fi
read -ra EXTRA <<< "${CMAKE_ARGS:-}"
for spec in "$@"; do
    name=${spec%%=*}; defs=${spec#*=}
    cmake -S "$ROOT" -B "$B" -DGPU_TARGET_ARCH="$ARCH" "${ARCH_ARGS[@]}" "${EXTRA[@]}" \
          "-DMM_EXP_DEFS=$defs" > "$EXP/build.cmake.log" 2>&1 || { tail -20 "$EXP/build.cmake.log"; exit 1; }
    make -C "$B" -j"$(nproc)" mt4g > "$EXP/build.make.log" 2>&1 || { grep -E "error|Error" "$EXP/build.make.log" | head -20; exit 1; }
    cp "$B/mt4g" "$EXP/bins/mt4g-$name"
    echo "built $name [$defs]"
done
