#!/bin/bash
# Run every config R times on one GPU, configs shuffled within each round, 2 s idle gap before each run.
# Usage: run.sh <R> <gpu-id> <cfg> [cfg ...]       binaries: bins/mt4g-<cfg>
# Output: $RESULTS/<cfg>/run<i>.txt (one latency in cycles per line); RESULTS defaults to results/
set -euo pipefail
EXP=$(cd "$(dirname "$0")/.." && pwd)
R=$1; GPU=$2; shift 2
RESULTS=${RESULTS:-$EXP/results}
export MT4G_EXP_MM_LATENCY_ONLY=1
for ((i = 1; i <= R; i++)); do
    mapfile -t order < <(printf '%s\n' "$@" | shuf --random-source=<(openssl enc -aes-256-ctr \
        -pass pass:"round$i" -nosalt -pbkdf2 </dev/zero 2>/dev/null))
    for cfg in "${order[@]}"; do
        T=$(mktemp -d); mkdir -p "$RESULTS/$cfg"
        sleep 2
        (cd "$T" && "$EXP/bins/mt4g-$cfg" -d "$GPU" --memory --raw -l . > /dev/null 2>&1)
        mv "$T"/results/*/*__Main_Memory_Latency.txt "$RESULTS/$cfg/run$i.txt"; rm -rf "$T"
    done
    echo "round $i: ${order[*]}"
done
