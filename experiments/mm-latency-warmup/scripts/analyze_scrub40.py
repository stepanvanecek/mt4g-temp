"""Scrub on vs off with 40 runs per config: run means, how many runs land at the high level, and permutation tests.

    python analyze_scrub40.py [RESULTS_DIR]     reads RESULTS_DIR/<cfg>/run<i>.txt (default results/scrub40),
                                                writes RESULTS_DIR/summary.md
Data: scripts/run.sh 40 <gpu> B C D E with RESULTS=results/scrub40.
"""
import sys
from pathlib import Path
import numpy as np

RES = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'results' / 'scrub40'
HIGH = 700   # a run is at the "high level" when its median latency is above this (levels are ~672 and ~732 cycles)
rng = np.random.default_rng(0)


def runs(cfg):
    files = sorted(RES.glob(f'{cfg}/run*.txt'), key=lambda f: int(f.stem[3:]))
    return [np.loadtxt(f) for f in files]


def permutation_p(a, b, n=100000):
    d = a.mean() - b.mean(); x = np.concatenate([a, b]); hits = 0
    for _ in range(n):
        rng.shuffle(x); hits += abs(x[:len(a)].mean() - x[len(a):].mean()) >= abs(d)
    return d, hits / n


means = {c: np.array([r.mean() for r in runs(c)]) for c in 'BCDE'}
medians = {c: np.array([np.median(r) for r in runs(c)]) for c in 'BCDE'}
rows = ['| cfg | scrub | warm-up | runs | mean of run means | sd of run means | runs at high level |', '|---|---|---|---|---|---|---|']
for c, scrub, warm in [('B', 'off', 'off'), ('D', 'on', 'off'), ('C', 'off', 'on'), ('E', 'on', 'on')]:
    m = means[c]
    rows.append(f'| {c} | {scrub} | {warm} | {len(m)} | {m.mean():.0f} | {m.std(ddof=1):.0f} | {(medians[c] > HIGH).sum()}/{len(m)} |')
rows += ['', '| comparison | difference (scrub - no scrub) | permutation p |', '|---|---|---|']
for a, b, label in [('E', 'C', 'E - C (warm-up on)'), ('D', 'B', 'D - B (warm-up off)')]:
    d, p = permutation_p(means[a], means[b])
    rows.append(f'| {label} | {d:+.1f} cycles | {p:.3f} |')
(RES / 'summary.md').write_text('\n'.join(rows) + '\n')
print('\n'.join(rows))
