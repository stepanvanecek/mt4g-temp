#!/bin/bash
# Does the scrub kernel change what the measuring kernel finds in L2? (AMD only: needs rocprofv3 and gfx90a.)
#  1. L2 counters (TCC_*) per kernel for configs C (no scrub) and E (scrub), 3 runs each -> results/scrub-check/counters.md
#  2. The two small L2 tests in scrub-check/ (cross-kernel and same-kernel)       -> results/scrub-check/l2_tests.txt
# Usage: scrub_check.sh [gpu-id]       (binaries bins/mt4g-C and bins/mt4g-E must exist: build_configs.sh C="MM_SCRUB=0" E="")
set -euo pipefail
EXP=$(cd "$(dirname "$0")/.." && pwd)
GPU=${1:-1}
source "$EXP/scripts/env.sh"
OUT=$EXP/results/scrub-check; mkdir -p "$OUT"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export MT4G_EXP_MM_LATENCY_ONLY=1
for cfg in C E; do for r in 1 2 3; do
    (cd "$T" && rocprofv3 --pmc TCC_HIT_sum TCC_MISS_sum TCC_EA_RDREQ_sum TCC_REQ_sum --kernel-include-regex mainMemoryLatency \
        --output-format csv -d "prof_${cfg}_$r" -- "$EXP/bins/mt4g-$cfg" -d "$GPU" --memory --raw -l . > /dev/null 2>&1)
done; done
python3 - "$T" > "$OUT/counters.md" <<'EOF'
import csv, collections, glob, sys
print('| run | kernel | L2 requests | L2 hits | L2 misses | main-memory reads |')
print('|---|---|---|---|---|---|')
for f in sorted(glob.glob(f'{sys.argv[1]}/prof_*/*/*_counter_collection.csv')):
    run = f.split('/prof_')[1].split('/')[0]
    d = collections.defaultdict(dict)
    for r in csv.DictReader(open(f)):
        d[r['Kernel_Name'].split('(')[0]][r['Counter_Name']] = int(float(r['Counter_Value']))
    for k in ('mainMemoryLatencyInitKernel', 'mainMemoryLatencyScrubKernel', 'mainMemoryLatencyKernel'):
        if k in d:
            c = d[k]
            print(f"| {run} | {k} | {c['TCC_REQ_sum']} | {c['TCC_HIT_sum']} | {c['TCC_MISS_sum']} | {c['TCC_EA_RDREQ_sum']} |")
EOF
for t in cross_kernel_l2 same_kernel_l2; do
    /opt/rocm/bin/hipcc --offload-arch=gfx90a -I/opt/amdgpu/include -O2 "$EXP/scrub-check/$t.cpp" -o "$T/$t" 2> /dev/null
done
{ echo "== cross_kernel_l2 (lines loaded by an earlier kernel)"; "$T/cross_kernel_l2" "$GPU"
  echo; echo "== same_kernel_l2 (lines loaded earlier in the same kernel)"; "$T/same_kernel_l2" "$GPU"; } > "$OUT/l2_tests.txt"
cat "$OUT/counters.md" "$OUT/l2_tests.txt"
